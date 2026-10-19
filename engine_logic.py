from datetime import date

def calculate_obligations_and_buffer(policy: dict):
    buffer_cfg = policy["buffer"]
    obligation_ids = set(buffer_cfg["obligationIds"])
    monthly_obligations = sum(
        sum(p["amount"] for p in ob["payees"])
        for ob in policy["obligations"]
        if ob["id"] in obligation_ids
    )
    required_buffer = (buffer_cfg["months"] * monthly_obligations) + buffer_cfg.get("extraUsd", 0.0)
    return monthly_obligations, required_buffer

def plan_treasury_actions(
    policy: dict,
    liquid_balance: float,
     current_date: date,
    market_price: float = 1.0,
    vault_balance: float = 0.0,
    vault_utilization_bps: int = 0,
    vault_withdrawals_paused: bool = False
):
    planned_actions = []
    depeg_cfg = policy["risk"]["depeg"]
    warn_below = depeg_cfg.get("warnBelow", 0.995)
    exit_below = depeg_cfg.get("exitBelow", 0.98)
    max_util_bps = policy.get("risk", {}).get("vault", {}).get("maxUtilizationBps", 9000)

    # 1. RISK CHECK (EXIT vs WARN)
    if market_price <= exit_below or vault_withdrawals_paused:
        reason = (
            f"CRITICAL: Price ${market_price:.3f} breached exit threshold ${exit_below}."
            if market_price <= exit_below
            else "CRITICAL: Vault withdrawals paused trigger activated."
        )
        planned_actions.append({
            "action": "EMERGENCY_EXIT",
            "tier": 3,
            "amount": vault_balance,
            "reason": reason
        })
        return planned_actions

    risk_warn = (market_price < warn_below) or (vault_utilization_bps > max_util_bps)

    # 2. DUE OBLIGATIONS (Check Calendar + Pre-Fund Shortfall if Needed)
    current_day = current_date.day
    period_ym = current_date.strftime("%Y-%m")
    for ob in policy["obligations"]:
        if ob["schedule"].get("dayOfMonth") == current_day:
            total_payout = sum(p["amount"] for p in ob["payees"])
            max_single = max((p["amount"] for p in ob["payees"]), default=0)

            # PRD 5.3a: If liquid < amount due, withdraw shortfall from vault first
            if liquid_balance < total_payout and vault_balance > 0:
                shortfall_for_payroll = min(total_payout - liquid_balance, vault_balance)
                planned_actions.append({
                    "action": "WITHDRAW_FROM_VAULT",
                    "tier": 0,
                    "amount": shortfall_for_payroll,
                    "reason": f"Pre-funding {ob['id']} shortfall of ${shortfall_for_payroll:,.2f} from vault."
                })
                liquid_balance += shortfall_for_payroll
                vault_balance -= shortfall_for_payroll

            planned_actions.append({
                "action": "PAY_BATCH",
                "tier": 0,
                "obligation_id": f"{ob['id']}:{period_ym}",
                "total_amount": total_payout,
                "max_single_amount": max_single,
                "reason": f"Scheduled recurring run for {ob['id']} on day {current_day}.",
                "recipients": [{"address": p["address"], "amount": p["amount"]} for p in ob["payees"]]
            })
            liquid_balance -= total_payout

    # 3. YIELD SWEEP & BUFFER RESTORATION (Respecting 60% Max Vault Share)
    _, required_buffer = calculate_obligations_and_buffer(policy)
    excess_cash = liquid_balance - required_buffer
    sweep_min = policy["sweep"]["minExcessUsd"]
    max_share_bps = policy["limits"].get("maxVaultShareBps", 6000)

    total_assets = liquid_balance + vault_balance
    max_vault_allowed = total_assets * (max_share_bps / 10000.0)
    available_vault_room = max(0.0, max_vault_allowed - vault_balance)

    if excess_cash >= sweep_min and not risk_warn and available_vault_room > 0:
        capped_room = max(0.0, available_vault_room - 1.0) if available_vault_room < excess_cash else available_vault_room
        deposit_amount = min(excess_cash, capped_room)
        if deposit_amount >= sweep_min:
            cap_note = f" (capped at {max_share_bps/100:.0f}% max vault share)" if deposit_amount < excess_cash else ""
            planned_actions.append({
                "action": "DEPOSIT_TO_VAULT",
                "tier": 0,
                "amount": deposit_amount,
                "reason": f"Sweeping ${deposit_amount:,.2f} spare cash to vault{cap_note}; buffer (${required_buffer:,.2f}) protected."
            })
    elif liquid_balance < required_buffer and vault_balance > 0:
        shortfall = min(required_buffer - liquid_balance, vault_balance)
        planned_actions.append({
            "action": "WITHDRAW_FROM_VAULT",
            "tier": 0,
            "amount": shortfall,
            "reason": f"Liquid balance is below required buffer (${required_buffer:,.2f}) by ${shortfall:,.2f}; restoring buffer."
        })

    if not planned_actions:
        planned_actions.append({"action": "NONE", "tier": 0, "reason": "Balances healthy; required buffer met and no obligations due today."})

    return planned_actions
