"""
FourEyes dashboard (Streamlit).

Two views, switched by the URL:
  ?view=landing  -> title + pricing (default)
  ?view=app      -> the dashboard (Log in goes here)

Run:  streamlit run app.py      (needs streamlit>=1.41)
"""
import calendar
import html
import json
import os
import re
import sqlite3
from datetime import date, datetime, timedelta, timezone

import altair as alt
import pandas as pd
import streamlit as st

from engine_logic import calculate_obligations_and_buffer

st.set_page_config(page_title="FourEyes", page_icon="◆", layout="wide", initial_sidebar_state="collapsed")

# =============================================================================
# BASESCAN LINKS
# -----------------------------------------------------------------------------
# Every "View on BaseScan" link is built automatically from the tx_hash column
# of decisions.db, so you never paste hashes here by hand.
#   - To point links at a different explorer (e.g. mainnet later), change
#     EXPLORER below.
#   - TX_HASH_OVERRIDES lets you force a link for a specific decision id
#     (the "id" column in decisions.db), e.g. {12: "0xabc..."}.
#   - A row with no hash links to the Treasury contract page instead.
# =============================================================================
EXPLORER = "https://sepolia.basescan.org"
TREASURY_ADDRESS = os.getenv("TREASURY_ADDRESS", "0xF265BbC1bdFeEa96e745225B7dd3f8E0e895c727")
TX_HASH_OVERRIDES = {}

POLICY_PATH = "policy.json"
DB_PATH = os.getenv("DECISIONS_DB_PATH", "decisions.db")
PENDING_PATH = "pending_policy_changes.json"
DECISIONS_PATH = "founder_decisions.json"
ADDR_RE = re.compile(r"^0x[a-fA-F0-9]{40}$")

# Founder signing in the dashboard is for a LOCAL demo only. Leave this unset on
# any hosted deployment: without it, Approve/Deny are recorded and the founder
# signs from their own wallet instead.
FOUNDER_KEY = os.getenv("FOUNDER_DEMO_PRIVATE_KEY")

ENGINE_ERROR = None
try:
    from engine import (
        fetch_onchain_state, vault_contract, treasury_contract, w3,
        init_db, log_decision_start, update_decision_result,
    )
except Exception as e:  # app still renders from policy.json and decisions.db
    fetch_onchain_state = vault_contract = treasury_contract = w3 = None
    init_db = log_decision_start = update_decision_result = None
    ENGINE_ERROR = str(e)

DB_COLUMNS = ["id", "created_at", "engine_time", "action", "tier", "rules", "inputs", "payee", "vault",
              "amount", "ref", "status", "tx_hash", "block", "explanation", "policy_hash"]
STATUS = {
    "CONFIRMED": ("Completed", "ok"),
    "PENDING": ("In progress", "ac"),
    "REJECTED_POLICY": ("Blocked by policy", "bad"),
    "REJECTED_PRE_FLIGHT": ("Blocked before sending", "bad"),
    "FAILED": ("Reverted on-chain", "bad"),
}
BLOCKED = {"REJECTED_POLICY", "REJECTED_PRE_FLIGHT", "FAILED"}
ACTIONS = {
    "PAY_BATCH": "Scheduled payout",
    "PAY": "Invoice payment",
    "REQUEST_APPROVAL": "Approval request",
    "DEPOSIT_TO_VAULT": "Moved to vault",
    "WITHDRAW_FROM_VAULT": "Withdrew from vault",
    "EMERGENCY_EXIT": "Emergency exit",
    "FOUNDER_APPROVAL": "Founder approval",
    "FOUNDER_DENIAL": "Founder denial",
    "FOUNDER_CHANGE": "Founder change",
    "NONE": "No action",
}
PAGES = ["Overview", "Approvals", "Payroll", "Vendors", "Treasury", "Security", "Audit log"]
PLANS = [
    {"name": "Starter", "m": 0, "y": 0, "for": "For small teams getting started", "feat": False,
     "items": ["Up to 10 payees and vendors", "Scheduled payroll and vendor runs", "On-chain caps and allowlist",
               "Depeg protection with automatic exit", "30-day decision log"]},
    {"name": "Growth", "m": 79, "y": 790, "for": "For growing teams that want yield", "feat": True,
     "items": ["Up to 50 payees and vendors", "Automatic sweep of spare cash to a vault", "Founder approval workflows",
               "Email alerts for anything that needs you", "12-month decision log"]},
    {"name": "Pro", "m": 199, "y": 1990, "for": "For companies running at scale", "feat": False,
     "items": ["Unlimited payees and vendors", "Yield across multiple vaults", "Multi-signer approvals",
               "Full audit trail, CSV export and reconciliation", "Priority support"]},
]

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap');
:root{--ink:#0E0E14;--muted:#6A6879;--faint:#A3A1B2;--line:#ECEBF3;--soft:#F6F5FB;--a1:#6D5DFC;--a2:#A855F7;--wm:#EFEDF7;
--ok-bg:#ECFDF3;--ok-fg:#067647;--ok-bd:#ABEFC6;--warn-bg:#FFFAEB;--warn-fg:#B54708;--warn-bd:#FEDF89;
--bad-bg:#FEF3F2;--bad-fg:#B42318;--bad-bd:#FECDCA;--ac-bg:#F4F3FF;--ac-fg:#5925DC;--ac-bd:#D9D6FE;}
html,body,.stApp,[class*="css"]{font-family:'Plus Jakarta Sans',system-ui,sans-serif;color:var(--ink);}
.stApp{background:radial-gradient(900px 380px at 92% -8%,#FDE4EE 0%,rgba(253,228,238,0) 60%),radial-gradient(800px 360px at 4% -10%,#ECE8FF 0%,rgba(236,232,255,0) 60%),#FFFFFF;}
#MainMenu,footer,header[data-testid="stHeader"]{visibility:hidden;height:0;}
.block-container{padding-top:1.2rem;max-width:1240px;}
.topbar{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;background:rgba(255,255,255,.82);border:1px solid var(--line);border-radius:999px;padding:8px 8px 8px 20px;margin-bottom:8px}
.brand{font-weight:800;font-size:16px;letter-spacing:-.01em}
.brand span{color:var(--muted);font-weight:500;margin-left:8px}
.rg{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.navlink{font-size:13px;color:var(--muted)!important;text-decoration:none!important;padding:6px 10px;border-radius:999px}
.hero{text-align:center;margin:44px auto 4px;max-width:760px}
.hero h1{font-size:clamp(36px,7vw,64px);line-height:1.04;font-weight:800;letter-spacing:-.04em;margin:18px 0 14px}
.grad{background:linear-gradient(90deg,var(--a1),var(--a2));-webkit-background-clip:text;background-clip:text;color:transparent}
.sub{color:var(--muted);font-size:16px;max-width:600px;margin:0 auto}
.cta{display:flex;gap:10px;justify-content:center;flex-wrap:wrap;margin-top:24px}
.chip{display:inline-flex;align-items:center;gap:8px;font-size:12px;padding:4px 12px 4px 4px;border-radius:999px;background:#fff;border:1px solid var(--line)}
.chip b{background:var(--ink);color:#fff;border-radius:999px;padding:2px 10px;font-weight:600}
.pill{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:500;padding:3px 10px;border-radius:999px;border:1px solid var(--line);color:var(--muted);background:#fff;white-space:nowrap}
.pill.ok{background:var(--ok-bg);color:var(--ok-fg);border-color:var(--ok-bd)}
.pill.warn{background:var(--warn-bg);color:var(--warn-fg);border-color:var(--warn-bd)}
.pill.bad{background:var(--bad-bg);color:var(--bad-fg);border-color:var(--bad-bd)}
.pill.ac{background:var(--ac-bg);color:var(--ac-fg);border-color:var(--ac-bd)}
.lbtn{display:inline-flex;align-items:center;justify-content:center;font-size:13px;font-weight:600;border-radius:999px;border:1px solid var(--line);background:#fff;color:var(--ink)!important;padding:9px 18px;text-decoration:none!important;white-space:nowrap}
.lbtn.dark{background:var(--ink);color:#fff!important;border-color:var(--ink)}
.lbtn.lg{padding:12px 22px;font-size:14px}
.apphead h1{font-size:clamp(26px,4vw,34px);font-weight:800;letter-spacing:-.03em;margin:22px 0 2px;padding:0}
.kgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:14px;margin-bottom:14px}
.card{background:#fff;border:1px solid var(--line);border-radius:18px;padding:18px 20px;margin-bottom:14px}
.k-top{display:flex;justify-content:space-between;align-items:center;gap:8px;font-size:13px;color:var(--muted)}
.k-val{font-size:28px;font-weight:700;letter-spacing:-.02em;margin:10px 0 12px;font-variant-numeric:tabular-nums}
.k-l1{font-size:13px;font-weight:600}
.k-l2{font-size:12px;color:var(--muted);margin-top:2px}
.sec{font-size:22px;font-weight:700;letter-spacing:-.02em;margin:6px 0 2px}
.muted{color:var(--muted);font-size:13px}
.ctitle{font-size:15px;font-weight:700;margin-bottom:6px}
.item{display:flex;justify-content:space-between;align-items:flex-start;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)}
.item:last-child{border-bottom:none}
.it{font-weight:600;font-size:14px}
.id{color:var(--muted);font-size:13px;margin-top:3px;line-height:1.5}
.ir{display:flex;flex-direction:column;align-items:flex-end;gap:6px;font-size:12px;flex:none}
.stApp a.tx{color:var(--a1)!important;font-size:12px;font-weight:500;text-decoration:none}
.bar{height:8px;border-radius:999px;background:var(--soft);overflow:hidden;margin-top:6px}
.bar>div{height:100%;background:linear-gradient(90deg,var(--a1),var(--a2));border-radius:999px}
.alloc{position:relative;height:16px;border-radius:999px;background:var(--soft);margin:14px 0 10px}
.alloc .liq{position:absolute;left:0;top:0;bottom:0;background:var(--ink);border-radius:999px 0 0 999px}
.alloc .vlt{position:absolute;top:0;bottom:0;background:linear-gradient(90deg,var(--a1),var(--a2));border-radius:0 999px 999px 0}
.alloc .cap{position:absolute;top:-6px;bottom:-6px;width:2px;background:var(--bad-fg)}
.legend{display:flex;gap:18px;font-size:12px;color:var(--muted);flex-wrap:wrap}
.sw{display:inline-block;width:10px;height:10px;border-radius:3px;margin-right:6px;vertical-align:-1px}
.ystats{display:flex;gap:24px;flex-wrap:wrap;margin:4px 0 2px}
.ystats div{font-size:12px;color:var(--muted)}
.ystats b{display:block;font-size:20px;color:var(--ink);font-weight:700;letter-spacing:-.02em}
/* page nav: radio styled as pill tabs */
div[data-testid="stRadio"]:has(input[value="Overview"]) div[role="radiogroup"]{gap:4px;background:#fff;border:1px solid var(--line);border-radius:999px;padding:5px;width:fit-content;flex-wrap:wrap}
div[data-testid="stRadio"]:has(input[value="Overview"]) label{margin:0;padding:7px 16px;border-radius:999px;cursor:pointer}
div[data-testid="stRadio"]:has(input[value="Overview"]) label > div:first-child{display:none}
div[data-testid="stRadio"]:has(input[value="Overview"]) label:has(input:checked){background:var(--ink)}
div[data-testid="stRadio"]:has(input[value="Overview"]) label:has(input:checked) p{color:#fff}
/* buttons */
.stButton>button,.stDownloadButton>button{border-radius:999px;border:1px solid var(--line);font-weight:600;padding:.4rem 1.1rem}
.stButton>button[kind="primary"],[data-testid="stBaseButton-primary"]{background:var(--ink)!important;color:#fff!important;border:none!important}
/* clickable rows */
.st-key-attention .stButton>button,.st-key-upcoming .stButton>button{width:100%;justify-content:flex-start;text-align:left;border:0;border-bottom:1px solid var(--line);border-radius:12px;background:transparent;padding:12px 10px;font-weight:600}
.st-key-attention .stButton>button:hover,.st-key-upcoming .stButton>button:hover{background:var(--soft)}
.st-key-attention .stButton>button p,.st-key-upcoming .stButton>button p{text-align:left}
[data-testid="stVerticalBlockBorderWrapper"]{border-radius:18px!important;border-color:var(--line)!important;background:#fff}
/* approvals */
.qtop{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:6px}
.qt{font-weight:700;font-size:15px}
.memo{font-size:13px;color:var(--muted);margin-top:6px}
.memo i{font-style:normal;color:var(--ink)}
.qmeta{display:flex;gap:6px 16px;flex-wrap:wrap;font-size:12px;color:var(--muted);margin-top:8px}
.qmeta code{font-family:'JetBrains Mono',monospace;font-size:12px;background:none;padding:0}
.qamt{font-size:22px;font-weight:700;letter-spacing:-.02em;text-align:right}
.qamt span{font-size:13px;color:var(--muted);font-weight:500}
.confirm{background:var(--soft);border-radius:14px;padding:12px 14px;font-size:13px}
.tiers{display:flex;gap:18px;flex-wrap:wrap;font-size:12px;color:var(--muted);margin:6px 0 14px}
.tiers span{display:inline-flex;align-items:center;gap:8px}
/* security numbered checks */
.steps{list-style:none;padding:0;margin:20px 0 30px;display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:28px;counter-reset:step}
@media (max-width:920px){.steps{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:520px){.steps{grid-template-columns:minmax(0,1fr)}}
.steps li{position:relative;padding-top:18px;border-top:2px solid var(--line);margin:0}
.steps li::after{content:"";position:absolute;top:-2px;left:0;width:44px;height:2px;background:linear-gradient(90deg,var(--a1),var(--a2))}
.steps li::before{counter-increment:step;content:counter(step,decimal-leading-zero);display:block;font-size:32px;font-weight:800;letter-spacing:-.04em;line-height:1;margin-bottom:14px;background:linear-gradient(90deg,var(--a1),var(--a2));-webkit-background-clip:text;background-clip:text;color:transparent}
.st{font-size:15px;font-weight:700;margin-bottom:6px}
.sd{font-size:13px;color:var(--muted);margin-bottom:12px;max-width:34ch}
/* pricing */
.pwrap{text-align:center;padding-top:36px;overflow:hidden}
.pwm{font-size:clamp(84px,18vw,190px);font-weight:800;letter-spacing:-.05em;color:var(--wm);line-height:1;margin:0;user-select:none}
.pgrid{display:grid;grid-template-columns:repeat(auto-fit,minmax(250px,1fr));gap:18px;max-width:1120px;margin:clamp(-115px,-10vw,-50px) auto 0;position:relative}
.pcard{text-align:left;background:rgba(255,255,255,.72);backdrop-filter:blur(16px);-webkit-backdrop-filter:blur(16px);border:1px solid var(--line);border-radius:22px;padding:26px;display:flex;flex-direction:column}
.pcard.feat{border-color:var(--ac-bd);box-shadow:0 0 0 4px var(--ac-bg)}
.pname{color:var(--muted);font-size:14px;display:flex;justify-content:space-between;align-items:center;min-height:24px}
.pprice{font-size:46px;font-weight:700;letter-spacing:-.03em;margin:8px 0 4px}
.pprice span{font-size:18px;color:var(--faint);font-weight:500}
.pfor{font-size:13px;color:var(--muted);margin-bottom:18px}
.pdiv{height:1px;background:var(--line);margin:0 -26px 10px}
.pli{display:flex;gap:10px;align-items:flex-start;font-size:14px;color:#3A3848;margin:12px 0}
.ck{width:20px;height:20px;border-radius:50%;border:1px solid var(--line);display:inline-flex;align-items:center;justify-content:center;font-size:11px;flex:none}
.pcard .lbtn{margin-top:auto;width:100%;padding:12px}
.pcard ul{list-style:none;padding:0;margin:0 0 22px}
"""


# ----------------------------------------------------------------------------- utils
def md(s):
    st.markdown("".join(line.strip() for line in s.splitlines()), unsafe_allow_html=True)


def esc(s):
    return html.escape("" if s is None else str(s))


def money(x):
    try:
        return f"${float(x):,.0f}"
    except (TypeError, ValueError):
        return "—"


def money_k(n):
    if n >= 1e6:
        return f"${n / 1e6:.2f}M"
    if n >= 1e3:
        return f"${n / 1e3:.0f}k" if n >= 1e5 else f"${n / 1e3:.1f}k"
    return f"${n:.0f}"


def pill(text, kind=""):
    return f'<span class="pill {kind}">{esc(text)}</span>'


def short(addr):
    return f"{addr[:6]}…{addr[-4:]}" if addr and len(addr) > 12 else (addr or "")


def safe_key(s):
    return re.sub(r"[^a-zA-Z0-9_-]", "_", str(s))


def read_json(path, default):
    if not os.path.exists(path):
        return default
    try:
        with open(path, "r") as f:
            return json.load(f)
    except (ValueError, OSError):
        return default


def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def now_iso():
    return datetime.now(timezone.utc).isoformat()


# ----------------------------------------------------------------------------- data
@st.cache_data(ttl=3, show_spinner=False)
def load_policy():
    with open(POLICY_PATH, "r") as f:
        return json.load(f)


@st.cache_data(ttl=3, show_spinner=False)
def get_state():
    if fetch_onchain_state is None:
        return None, ENGINE_ERROR or "Engine not available"
    try:
        return fetch_onchain_state(), None
    except Exception as e:
        return None, str(e)


@st.cache_data(ttl=30, show_spinner=False)
def get_vault_rate():
    try:
        return vault_contract.functions.rateBps().call() / 10000.0
    except Exception:
        return None


def parse_rules(rules):
    try:
        return json.loads(rules or "{}")
    except (ValueError, TypeError):
        return {}


@st.cache_data(ttl=3, show_spinner=False)
def load_decisions():
    if not os.path.exists(DB_PATH):
        df = pd.DataFrame(columns=DB_COLUMNS)
    else:
        conn = sqlite3.connect(DB_PATH)
        df = pd.read_sql_query("SELECT * FROM decisions ORDER BY id DESC", conn)
        conn.close()
    df["amount"] = pd.to_numeric(df["amount"], errors="coerce").fillna(0.0)
    df["obligation"] = df["rules"].apply(lambda r: parse_rules(r).get("obligation_id") or "")
    df["ts"] = pd.to_datetime(df["created_at"], utc=True, errors="coerce")
    df["simulated"] = df["tx_hash"].fillna("").astype(str).str.startswith("0xdebug")
    return df


@st.cache_data(ttl=30, show_spinner=False)
def request_ids():
    """Maps an approval request's ref (0x...) to its on-chain payment id."""
    out = {}
    if treasury_contract is None:
        return out
    try:
        latest = w3.eth.block_number
        logs = treasury_contract.events.PaymentRequested.get_logs(from_block=max(0, latest - 50_000))
        for log in logs:
            args = dict(log["args"])
            pid = args.get("id", args.get("paymentId"))
            ref = args.get("ref")
            if pid is not None and ref is not None:
                out["0x" + bytes(ref).hex()] = int(pid)
    except Exception:
        pass
    return out


# ----------------------------------------------------------------------------- display helpers
def tx_url(row):
    h = TX_HASH_OVERRIDES.get(row.get("id")) or row.get("tx_hash") or ""
    if h and not str(h).startswith("0xdebug"):
        return f"{EXPLORER}/tx/{h}"
    return f"{EXPLORER}/address/{TREASURY_ADDRESS}"


def tx_html(row):
    if bool(row.get("simulated")) and not TX_HASH_OVERRIDES.get(row.get("id")):
        return '<span class="muted">Simulated, no transaction</span>'
    return f'<a class="tx" href="{esc(tx_url(row))}" target="_blank" rel="noopener">View on BaseScan ↗</a>'


def status_pill(row, open_ids=frozenset()):
    if bool(row.get("simulated")):
        return pill("Simulated test run", "ac")
    if row.get("action") == "REQUEST_APPROVAL" and row.get("status") == "CONFIRMED":
        return pill("Awaiting founder", "warn") if f"req:{row.get('ref')}" in open_ids else pill("Resolved", "ok")
    label, kind = STATUS.get(row.get("status"), (row.get("status") or "Unknown", ""))
    return pill(label, kind)


def when(row):
    ts = row.get("ts")
    return ts.strftime("%b %d, %H:%M UTC") if pd.notna(ts) else ""


def kpi(label, value, badge, line1, line2):
    return (f'<div class="card" style="margin:0"><div class="k-top"><span>{esc(label)}</span>{badge}</div>'
            f'<div class="k-val">{esc(value)}</div><div class="k-l1">{esc(line1)}</div>'
            f'<div class="k-l2">{esc(line2)}</div></div>')


def activity_row(row, open_ids=frozenset()):
    title = f"{ACTIONS.get(row['action'], row['action'])} · {money(row['amount'])}"
    return (f'<div class="item"><div><div class="it">{esc(title)}</div><div class="id">{esc(row.get("explanation") or "")}</div></div>'
            f'<div class="ir">{status_pill(row, open_ids)}<span class="muted">{esc(when(row))}</span>{tx_html(row)}</div></div>')


def risk_state(state, policy):
    if not state:
        return "Offline", "warn"
    depeg = policy.get("risk", {}).get("depeg", {})
    vault = policy.get("risk", {}).get("vault", {})
    price = state.get("token_price", 1.0)
    if state.get("paused"):
        return "Agent paused", "warn"
    if price <= depeg.get("exitBelow", 0.98) or (state.get("vault_withdrawals_paused") and vault.get("exitOnWithdrawalsPaused", True)):
        return "Protecting funds", "bad"
    if price < depeg.get("warnBelow", 0.995) or state.get("vault_utilization_bps", 0) > vault.get("maxUtilizationBps", 9000):
        return "Watching closely", "warn"
    return "All systems normal", "ok"


def next_run(day_of_month, today):
    y, m = today.year, today.month
    cand = date(y, m, min(day_of_month, calendar.monthrange(y, m)[1]))
    if cand < today:
        y, m = (y + 1, 1) if m == 12 else (y, m + 1)
        cand = date(y, m, min(day_of_month, calendar.monthrange(y, m)[1]))
    return cand


def obligation(policy, ob_id):
    return next((ob for ob in policy["obligations"] if ob["id"] == ob_id), None)


def payee_index(policy):
    return {p["address"].lower(): (p, ob["id"]) for ob in policy["obligations"] for p in ob["payees"]}


def group_of(p):
    name = p["name"]
    return p.get("team") or p.get("category") or (name.rsplit(" contributor", 1)[0] if " contributor" in name else "Vendor")


# ----------------------------------------------------------------------------- yield projection
def simulate_yield(policy, liquid, vault, rate, days, start):
    """Replays the agent's own policy day by day: paydays, buffer top-ups, sweeps, max vault share."""
    _, buffer = calculate_obligations_and_buffer(policy)
    min_sweep = policy.get("sweep", {}).get("minExcessUsd", 50_000)
    max_share = policy.get("sweep", {}).get("maxVaultShareBps", policy["limits"].get("maxVaultShareBps", 6000)) / 10000.0
    runs = [(ob["schedule"]["dayOfMonth"], sum(p["amount"] for p in ob["payees"])) for ob in policy["obligations"]]
    L, V, cum, rows = float(liquid), float(vault), 0.0, []
    for i in range(days + 1):
        d = start + timedelta(days=i)
        if i > 0:
            for day, amt in runs:
                if d.day == day:
                    if L < amt:
                        w = min(amt - L, V)
                        V -= w
                        L += w
                    L = max(0.0, L - amt)
            if L < buffer and V > 0:
                w = min(buffer - L, V)
                V -= w
                L += w
            excess, room = L - buffer, max(0.0, max_share * (L + V) - V)
            if excess >= min_sweep and room > 0:
                dep = min(excess, room)
                L -= dep
                V += dep
            interest = V * rate / 365
            V += interest
            cum += interest
        rows.append({"Date": pd.Timestamp(d), "Interest": cum, "Vault": V})
    return pd.DataFrame(rows)


def render_yield_card(policy, state, key, default_days):
    head, seg = st.columns([3, 2])
    with head:
        md('<div class="ctitle">Projected yield</div><div class="muted">Interest the vault earns while the agent covers '
           'every scheduled payout. Dashed lines mark paydays.</div>')
    with seg:
        choice = st.radio("Horizon", ["30 days", "90 days", "6 months"], index=["30 days", "90 days", "6 months"].index(default_days),
                          horizontal=True, key=f"h_{key}", label_visibility="collapsed")
    days = {"30 days": 30, "90 days": 90, "6 months": 182}[choice]
    if not state:
        st.caption("The projection appears once live balances load.")
        return
    rate_onchain = get_vault_rate()
    rate = rate_onchain if rate_onchain is not None else 0.05
    df = simulate_yield(policy, state["liquid_balance"], state["vault_balance"], rate, days, date.today())
    total = df["Interest"].iloc[-1]
    md(f'<div class="ystats"><div><b>{money(total)}</b>Projected interest</div>'
       f'<div><b>{money_k(df["Vault"].mean())}</b>Average in vault</div>'
       f'<div><b>{rate:.1%}</b>Vault rate{"" if rate_onchain is not None else " (assumed)"}</div></div>')
    pay_days = sorted({ob["schedule"]["dayOfMonth"] for ob in policy["obligations"]})
    rules = df[df["Date"].dt.day.isin(pay_days)].iloc[1:] if len(df) > 1 else df.iloc[0:0]
    area = alt.Chart(df).mark_area(
        line={"color": "#6D5DFC", "strokeWidth": 2.5},
        color=alt.Gradient(gradient="linear", x1=1, x2=1, y1=1, y2=0,
                           stops=[alt.GradientStop(color="#FFFFFF", offset=0), alt.GradientStop(color="#C4B5FD", offset=1)]),
    ).encode(
        x=alt.X("Date:T", title=None, axis=alt.Axis(format="%b %d")),
        y=alt.Y("Interest:Q", title=None, axis=alt.Axis(format="$,.0f")),
        tooltip=[alt.Tooltip("Date:T", format="%b %d"), alt.Tooltip("Interest:Q", format="$,.0f", title="Interest earned"),
                 alt.Tooltip("Vault:Q", format="$,.0f", title="In vault")],
    )
    paydays = alt.Chart(rules).mark_rule(color="#D9D6FE", strokeDash=[3, 4]).encode(x="Date:T")
    end = df.tail(1)
    dot = alt.Chart(end).mark_circle(size=70, color="#6D5DFC", stroke="#FFFFFF", strokeWidth=2).encode(x="Date:T", y="Interest:Q")
    label = alt.Chart(end).mark_text(align="right", dx=-10, dy=-12, fontWeight=600, color="#0E0E14").encode(
        x="Date:T", y="Interest:Q", text=alt.Text("Interest:Q", format="$,.0f"))
    chart = alt.layer(paydays, area, dot, label).properties(height=250).configure_view(strokeWidth=0).configure_axis(
        grid=True, gridColor="#F0EFF6", domain=False, tickColor="#F0EFF6", labelColor="#6A6879")
    st.altair_chart(chart, use_container_width=True)


# ----------------------------------------------------------------------------- approvals
def build_queue(df, policy, decisions, pending):
    """Tier 2: nothing moves until the founder approves. Tier 1: the agent acted and wants a check."""
    idx = payee_index(policy)
    items = []
    for p in pending:
        qid = f"add:{p['address'].lower()}"
        if qid in decisions:
            continue
        items.append({"id": qid, "tier": 2, "kind": "payee", "p": p, "amount": p["amount"], "address": p["address"],
                      "title": f"Add {p['name']} to {'payroll' if p['kind'] == 'payroll' else 'vendors'}",
                      "short": f"Sign: add {p['name']}", "detail": f"{p['group']} · {money(p['amount'])}/month",
                      "why": "New payees go on the on-chain allowlist only with your signature.",
                      "raised": p.get("requestedAt", "")[:16].replace("T", " ")})
    live = df[~df["simulated"]]
    for _, r in live[(live["action"] == "REQUEST_APPROVAL") & (live["status"] == "CONFIRMED")].iterrows():
        qid = f"req:{r['ref']}"
        if qid in decisions:
            continue
        p, _ = idx.get((r["payee"] or "").lower(), ({"name": short(r["payee"])}, None))
        items.append({"id": qid, "tier": 2, "kind": "invoice", "row": r, "amount": r["amount"], "address": r["payee"],
                      "ref": r["ref"], "title": f"Invoice from {p['name']}",
                      "short": f"Approve {money(r['amount'])} to {p['name']}", "detail": "Above your approval threshold",
                      "why": "Above your approval threshold, so the agent queued it on-chain and paid nothing.",
                      "raised": when(r)})
    for _, r in live[(live["action"] == "PAY") & (live["status"] == "CONFIRMED")].iterrows():
        qid = f"rev:{r['id']}"
        known = idx.get((r["payee"] or "").lower())
        if qid in decisions or not known or r["amount"] <= known[0]["amount"] * 1.10:
            continue
        p = known[0]
        pct = (r["amount"] / p["amount"] - 1) * 100
        items.append({"id": qid, "tier": 1, "kind": "review", "row": r, "amount": r["amount"], "address": r["payee"],
                      "title": f"Check payment to {p['name']}", "short": f"Check {money(r['amount'])} paid to {p['name']}",
                      "detail": "Higher than this vendor usually charges",
                      "why": f"Paid automatically because it is under your threshold, but it is {pct:.0f}% above this vendor's usual {money(p['amount'])}.",
                      "raised": when(r)})
    exits = live[(live["action"] == "EMERGENCY_EXIT") & (live["status"] == "CONFIRMED")]
    if not exits.empty:
        r = exits.iloc[0]
        qid = f"exit:{r['id']}"
        if qid not in decisions:
            items.append({"id": qid, "tier": 1, "kind": "exit", "row": r, "amount": r["amount"], "address": TREASURY_ADDRESS,
                          "title": "Emergency exit from the vault", "short": "Check the emergency exit",
                          "detail": "The agent pulled funds back to the wallet",
                          "why": r.get("explanation") or "The agent pulled funds out of the vault after a risk signal.",
                          "raised": when(r)})
    return items


CONFIRM_TEXT = {
    ("invoice", True): ("Pay {amt} to {name}? This is signed by the founder wallet and counts toward today's daily cap.", "Sign and approve"),
    ("invoice", False): ("Deny this payment? Nothing is paid and the request is closed on-chain.", "Deny payment"),
    ("review", True): ("Mark this payment as checked? No money moves.", "Mark as checked"),
    ("review", False): ("Remove {name} from the allowlist? The agent can't pay them again until you add them back. The {amt} already paid stays paid.", "Remove from allowlist"),
    ("exit", True): ("Mark the emergency exit as checked? The agent resumes normal sweeps once the risk clears.", "Mark as checked"),
    ("exit", False): ("Pause the agent? It stops all payments and vault moves until you unpause. Emergency exit still works.", "Pause agent"),
    ("payee", True): ("Add {name} to the allowlist? This is signed by the founder wallet and they're paid from the next run.", "Sign and add"),
    ("payee", False): ("Discard this addition? {name} won't be added or paid.", "Discard"),
}


def owner_send(call):
    """Signs and sends a founder-only transaction. Local demo only (FOUNDER_DEMO_PRIVATE_KEY)."""
    from eth_account import Account
    from web3 import Web3
    acct = Account.from_key(FOUNDER_KEY)
    call.call({"from": acct.address})  # simulate first: surfaces the revert reason
    tx = call.build_transaction({"from": acct.address, "nonce": w3.eth.get_transaction_count(acct.address, "pending"),
                                 "chainId": w3.eth.chain_id})
    signed = acct.sign_transaction(tx)
    h = w3.eth.send_raw_transaction(signed.raw_transaction)
    receipt = w3.eth.wait_for_transaction_receipt(h, timeout=120)
    if receipt.status != 1:
        raise RuntimeError("The transaction reverted on-chain.")
    return Web3.to_hex(h), receipt.blockNumber


def log_founder(action, item, status, tx_hash, block, explanation):
    if log_decision_start is None:
        return
    try:
        init_db()
        row_id = log_decision_start(date.today().isoformat(),
                                    {"action": action, "tier": item["tier"], "amount": item["amount"],
                                     "payee": item.get("address"), "reason": explanation},
                                    {}, item.get("ref") or "0x0", "PENDING", policy_hash_hex(), explanation)
        update_decision_result(row_id, status, tx_hash, block, explanation)
    except Exception:
        pass


def canonical_policy_bytes(policy):
    from web3 import Web3
    return bytes(Web3.keccak(text=json.dumps(policy, separators=(",", ":"), sort_keys=True)))


def policy_hash_hex():
    try:
        return "0x" + canonical_policy_bytes(load_policy()).hex()
    except Exception:
        return "0x0"


def execute_decision(item, approve, policy):
    """Returns (ok, label, note). Signs on-chain only when FOUNDER_DEMO_PRIVATE_KEY is set."""
    can_sign = bool(FOUNDER_KEY) and treasury_contract is not None
    kind, name = item["kind"], item["title"]
    tx_hash = block = None
    try:
        if kind == "invoice":
            pid = request_ids().get(item["ref"])
            if can_sign and pid is not None:
                fn = treasury_contract.functions.approvePayment(pid) if approve else treasury_contract.functions.rejectPayment(pid)
                tx_hash, block = owner_send(fn)
            note = (f"{money(item['amount'])} paid." if approve else "Request closed. Nothing was paid.") if tx_hash else \
                   "Recorded. Sign it from the founder wallet to finish."
            log_founder("FOUNDER_APPROVAL" if approve else "FOUNDER_DENIAL", item, "CONFIRMED" if tx_hash else "PENDING",
                        tx_hash, block, f"Founder {'approved' if approve else 'denied'} {name.lower()} ({money(item['amount'])}). {note}")
            return True, ("Approved" if approve else "Denied"), note, tx_hash
        if kind == "review":
            if approve:
                return True, "Checked", "Marked as checked. No money moved.", None
            if can_sign:
                tx_hash, block = owner_send(treasury_contract.functions.setPayee(item["address"], False))
            note = "Removed from the allowlist." if tx_hash else "Recorded. Remove them from the founder wallet to finish."
            log_founder("FOUNDER_CHANGE", item, "CONFIRMED" if tx_hash else "PENDING", tx_hash, block, f"Founder removed {short(item['address'])} from the allowlist. {note}")
            return True, "Removed", note, tx_hash
        if kind == "exit":
            if approve:
                return True, "Checked", "Emergency exit marked as checked.", None
            if can_sign:
                tx_hash, block = owner_send(treasury_contract.functions.pause())
            note = "Agent paused." if tx_hash else "Recorded. Pause the agent from the founder wallet to finish."
            log_founder("FOUNDER_CHANGE", item, "CONFIRMED" if tx_hash else "PENDING", tx_hash, block, f"Founder paused the agent. {note}")
            return True, "Agent paused", note, tx_hash
        if kind == "payee":
            pending = read_json(PENDING_PATH, [])
            p = item["p"]
            if not approve:
                write_json(PENDING_PATH, [x for x in pending if x["address"].lower() != p["address"].lower()])
                return True, "Discarded", "Not added.", None
            if not can_sign:
                for x in pending:
                    if x["address"].lower() == p["address"].lower():
                        x["status"] = "Approved, waiting for founder signature"
                write_json(PENDING_PATH, pending)
                return True, "Approved", "Recorded. Sign it from the founder wallet to make it live.", None
            # Signed path: allowlist on-chain, update policy.json, then publish the new policy fingerprint.
            tx_hash, block = owner_send(treasury_contract.functions.setPayee(p["address"], True))
            new_policy = json.loads(json.dumps(policy))
            ob = obligation(new_policy, p["kind"])
            entry = {"name": p["name"], "address": p["address"], "amount": p["amount"]}
            entry["team" if p["kind"] == "payroll" else "category"] = p["group"]
            ob["payees"].append(entry)
            owner_send(treasury_contract.functions.setPolicyHash(canonical_policy_bytes(new_policy)))
            write_json(POLICY_PATH, new_policy)
            write_json(PENDING_PATH, [x for x in pending if x["address"].lower() != p["address"].lower()])
            log_founder("FOUNDER_CHANGE", item, "CONFIRMED", tx_hash, block, f"Founder added {p['name']} ({short(p['address'])}) to the allowlist.")
            return True, "Added", f"{p['name']} is live and paid from the next run.", tx_hash
    except Exception as e:
        return False, "Failed", str(e), None
    return False, "Failed", "Unknown item.", None


# ----------------------------------------------------------------------------- navigation
def nav(page, focus=None):
    st.session_state.page = page
    st.session_state.focus = focus


def ask(item_id, approve):
    st.session_state.confirm = {item_id: approve}


def cancel_ask():
    st.session_state.confirm = {}


# ============================================================================= LANDING
md(f"<style>{CSS}</style>")
view = st.query_params.get("view", "landing")

if view != "app":
    md('<div class="topbar"><div class="brand">◆ FourEyes</div><div class="rg">'
       '<a class="navlink" href="#pricing">Pricing</a><a class="lbtn dark" href="?view=app" target="_self">Log in</a></div></div>'
       '<div class="hero"><span class="chip"><b>New</b>Autonomous treasury, on-chain limits</span>'
       '<h1>Your treasury,<br><span class="grad">on autopilot</span></h1>'
       '<p class="sub">Pays your team and vendors, keeps a safety buffer, and puts spare cash to work, always inside the limits you signed.</p>'
       '<div class="cta"><a class="lbtn dark lg" href="?view=app" target="_self">Log in</a><a class="lbtn lg" href="#pricing">See pricing</a></div></div>')
    yearly = st.session_state.get("yearly", False)
    cards = ""
    for p in PLANS:
        price = "Free" if p["m"] == 0 else f"${(p['y'] if yearly else p['m']):,}<span>{'/yr' if yearly else '/mo'}</span>"
        items = "".join(f'<li class="pli"><span class="ck">✓</span><span>{esc(i)}</span></li>' for i in p["items"])
        cards += (f'<div class="pcard{" feat" if p["feat"] else ""}"><div class="pname">{esc(p["name"])}{pill("Most popular", "ac") if p["feat"] else ""}</div>'
                  f'<div class="pprice">{price}</div><div class="pfor">{esc(p["for"])}</div><div class="pdiv"></div><ul>{items}</ul>'
                  f'<a class="lbtn{" dark" if p["feat"] else ""}" href="?view=app" target="_self">Get started</a></div>')
    md(f'<div class="pwrap" id="pricing"><p class="pwm">Pricing</p><div class="pgrid">{cards}</div></div>')
    _, mid, _ = st.columns([2, 1, 2])
    with mid:
        st.toggle("Billed yearly · 2 months free", key="yearly")
    st.stop()

# ============================================================================= APP
try:
    policy = load_policy()
except Exception as e:
    st.error(f"Couldn't load policy.json: {e}")
    st.stop()

if "page" not in st.session_state:
    st.session_state.page = "Overview"
if "next_page" in st.session_state:  # set by the add-payee dialog, applied before the nav widget renders
    st.session_state.page = st.session_state.pop("next_page")
st.session_state.setdefault("focus", None)
st.session_state.setdefault("confirm", {})

monthly, required_buffer = calculate_obligations_and_buffer(policy)
limits = policy["limits"]
max_share = policy.get("sweep", {}).get("maxVaultShareBps", limits.get("maxVaultShareBps", 6000)) / 10000.0
today = date.today()
company = policy.get("company", {}).get("name", "Your company")
decisions = read_json(DECISIONS_PATH, {})
pending = read_json(PENDING_PATH, [])
pending_open = [p for p in pending if not p.get("status", "").startswith("Approved")]
df = load_decisions()
queue = build_queue(df, policy, decisions, pending_open)
open_ids = frozenset(q["id"] for q in queue)
state, state_err = get_state()

with st.sidebar:
    st.markdown("**Policy at a glance**")
    st.caption(f"Buffer: {policy['buffer']['months']} months of obligations ({money(required_buffer)})")
    st.caption(f"Approval threshold: {money(limits['approvalThresholdUsd'])}")
    st.caption(f"Hard cap per payment: {money(limits['perPaymentCapUsd'])}")
    st.caption(f"Daily cap: {money(limits['dailyPaymentCapUsd'])}")
    st.caption(f"Max in vault: {max_share:.0%}")
    st.caption("Founder signing: " + ("on (local demo key)" if FOUNDER_KEY else "off, decisions are recorded for the founder wallet"))
    live = st.toggle("Live refresh (5s)", value=True)
    if st.button("Refresh now", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

risk_label, risk_kind = risk_state(state, policy)
md(f'<div class="topbar"><div class="brand">◆ FourEyes<span>{esc(company)}</span></div><div class="rg">'
   f'{pill("Base Sepolia", "ac")}{pill(risk_label, risk_kind)}<a class="lbtn" href="?view=landing" target="_self">Log out</a></div></div>')
hour = datetime.now().hour
n = len(queue)
sub = (f"{n} item{'s' if n != 1 else ''} need{'' if n != 1 else 's'} your approval. " if n else "Nothing needs you right now. ") + \
      ("Payroll is funded and the USDC peg is healthy." if risk_kind == "ok" else "Check the status in the top bar.")
md(f'<div class="apphead"><h1>Good {"morning" if hour < 12 else "afternoon" if hour < 18 else "evening"}, {esc(company)}</h1>'
   f'<div class="muted">{esc(sub)}</div></div>')
if not state:
    st.warning("Live balances are unavailable. Check the RPC URL and .env, then press Refresh now.")
    with st.expander("Technical details"):
        st.code(state_err or "Unknown error")

page = st.radio("Section", PAGES, key="page", horizontal=True, label_visibility="collapsed")
if n:
    st.caption(f"Approvals: {n} waiting")


# ----------------------------------------------------------------------------- KPI row (live)
def render_kpis():
    s, _ = get_state()
    d = load_decisions()
    if not s:
        return
    liquid, vault = s["liquid_balance"], s["vault_balance"]
    total = liquid + vault
    runway = total / monthly if monthly else 0
    coverage = liquid / required_buffer if required_buffer else 0
    share = vault / total if total else 0
    price = s.get("token_price", 1.0)
    mask = (d["status"] == "CONFIRMED") & d["action"].isin(["PAY", "PAY_BATCH", "FOUNDER_APPROVAL"]) & ~d["simulated"]
    mask &= d["ts"].dt.strftime("%Y-%m") == today.strftime("%Y-%m")
    md('<div class="kgrid">' + "".join([
        kpi("Total treasury", money(total), pill(f"{runway:.1f} mo runway", "ac"), "Across wallet and vault", f"Monthly obligations {money(monthly)}"),
        kpi("Safety buffer", money(liquid), pill(f"{coverage:.0%} covered", "ok" if coverage >= 1 else "warn"), "Instantly available cash", f"Target {money(required_buffer)}"),
        kpi("Earning yield", money(vault), pill(f"{share:.0%} of {max_share:.0%} max", "ac"), "Spare cash in the vault", "Never more than the max share"),
        kpi("Paid this month", money(d.loc[mask, "amount"].sum()), pill(f"{money(s.get('spent_today', 0))} today"), "Payroll, vendors and invoices", f"Daily cap {money(limits['dailyPaymentCapUsd'])}"),
        kpi("USDC price", f"${price:.4f}", pill("Peg healthy" if price >= 0.995 else "Peg under watch", "ok" if price >= 0.995 else "warn"), "From the price feed", "Exit below $0.98"),
    ]) + "</div>")


# ----------------------------------------------------------------------------- pages
if page == "Overview":
    st.fragment(run_every=5 if live else None)(render_kpis)()
    with st.container(border=True):
        render_yield_card(policy, state, "ov", "90 days")
    left, right = st.columns([1.15, 1])
    with left:
        with st.container(border=True, key="attention"):
            md('<div class="ctitle">Needs your attention</div>')
            if not queue:
                st.caption("Nothing needs you right now. The agent is handling routine payments within your policy.")
            for q in queue:
                st.button(f"{q['short']}  ·  Tier {q['tier']}  ›", key=f"go_{safe_key(q['id'])}", help=q["detail"],
                          on_click=nav, args=("Approvals", q["id"]), use_container_width=True)
    with right:
        with st.container(border=True, key="upcoming"):
            md('<div class="ctitle">Coming up</div>')
            for ob_id, label in (("payroll", "Payroll"), ("vendors", "Vendors")):
                ob = obligation(policy, ob_id)
                if not ob:
                    continue
                due = next_run(ob["schedule"]["dayOfMonth"], today)
                amt = sum(p["amount"] for p in ob["payees"])
                funded = bool(state) and state["liquid_balance"] >= amt
                st.button(f"{label} · {due.strftime('%b %d')}  ·  {len(ob['payees'])} payees · {money(amt)}  ·  "
                          f"{'Funded' if funded else 'Will withdraw from vault'}  ›",
                          key=f"up_{ob_id}", on_click=nav, args=(label,), use_container_width=True)
            st.button(f"Vault check · Daily  ·  Sweeps spare cash above the {money(required_buffer)} buffer  ›",
                      key="up_vault", on_click=nav, args=("Treasury",), use_container_width=True)
    feed = df[df["action"] != "NONE"].head(6)
    with st.container(border=True):
        h1, h2 = st.columns([4, 1])
        h1.markdown('<div class="ctitle">Recent agent activity</div>', unsafe_allow_html=True)
        h2.button("Full log ›", key="to_log", on_click=nav, args=("Audit log",))
        md("".join(activity_row(r, open_ids) for _, r in feed.iterrows()) or '<div class="muted">No agent activity yet. Run engine.py to start.</div>')

elif page == "Approvals":
    md('<div class="sec">Approvals</div><div class="muted">Payments and changes that are waiting on you.</div>'
       '<div class="tiers"><span>' + pill("Tier 2", "warn") + 'Nothing moves until you approve</span><span>' + pill("Tier 1", "ac") +
       'The agent already acted, and wants you to check it</span></div>')
    if not FOUNDER_KEY:
        st.caption("Founder signing is off here. Your decisions are recorded, and on-chain steps are finished from the founder wallet.")
    focus = st.session_state.get("focus")
    ordered = sorted(queue, key=lambda q: q["id"] != focus)
    if focus and any(q["id"] == focus for q in queue):
        md(f"<style>.st-key-q_{safe_key(focus)}{{box-shadow:0 0 0 3px #D9D6FE;background:#F4F3FF!important}}</style>")
    if not ordered:
        with st.container(border=True):
            st.caption(f"You're all caught up. Anything above your {money(limits['approvalThresholdUsd'])} threshold, or anything the agent flags, shows up here.")
    for q in ordered:
        with st.container(border=True, key=f"q_{safe_key(q['id'])}"):
            left, right = st.columns([3, 1.3])
            kind_label = {"payee": "Allowlist change", "invoice": "Invoice", "review": "Paid, needs a check", "exit": "Agent acted"}[q["kind"]]
            link = tx_html(q["row"]) if "row" in q else ""
            with left:
                md(f'<div class="qtop">{pill("Tier 2", "warn") if q["tier"] == 2 else pill("Tier 1", "ac")}{pill(kind_label)}</div>'
                   f'<div class="qt">{esc(q["title"])}</div><div class="memo">{esc(q["why"])}</div>'
                   f'<div class="qmeta"><span>Wallet <code>{esc(short(q["address"]))}</code></span>'
                   f'{"<span>" + esc(q["p"]["group"]) + "</span>" if q["kind"] == "payee" else ""}'
                   f'<span>Raised {esc(q["raised"])}</span>{link}</div>')
            with right:
                md(f'<div class="qamt">{money(q["amount"])}{"<span>/month</span>" if q["kind"] == "payee" else ""}</div>')
                b1, b2 = st.columns(2)
                b1.button("Deny", key=f"no_{safe_key(q['id'])}", on_click=ask, args=(q["id"], False), use_container_width=True)
                b2.button("Approve", key=f"yes_{safe_key(q['id'])}", type="primary", on_click=ask, args=(q["id"], True), use_container_width=True)
            asked = st.session_state.confirm.get(q["id"])
            if asked is not None:
                name = q["p"]["name"] if q["kind"] == "payee" else q["title"].split(" from ")[-1].replace("Check payment to ", "")
                text, label = CONFIRM_TEXT[(q["kind"], asked)]
                md(f'<div class="confirm">{esc(text.format(amt=money(q["amount"]), name=name))}</div>')
                c1, c2, _ = st.columns([1, 1.4, 3])
                c1.button("Cancel", key=f"cx_{safe_key(q['id'])}", on_click=cancel_ask, use_container_width=True)
                if c2.button(label, key=f"go2_{safe_key(q['id'])}", type="primary", use_container_width=True):
                    with st.spinner("Working…"):
                        ok, result, note, tx = execute_decision(q, asked, policy)
                    if ok:
                        decisions[q["id"]] = {"title": q["title"], "approved": asked, "label": result, "note": note,
                                              "tx": tx, "at": now_iso()}
                        write_json(DECISIONS_PATH, decisions)
                        st.session_state.confirm = {}
                        st.session_state.focus = None
                        st.cache_data.clear()
                        st.toast(f"{result}. {note}")
                        st.rerun()
                    else:
                        st.error(f"That didn't go through: {note}")
    todays = [d for d in decisions.values() if d.get("at", "")[:10] == datetime.now(timezone.utc).date().isoformat()]
    if todays:
        rows = "".join(
            f'<div class="item"><div><div class="it">{esc(d["title"])}</div><div class="id">{esc(d["note"])}</div></div>'
            f'<div class="ir">{pill(d["label"], "ok" if d["approved"] else "bad")}<span class="muted">Today, {esc(d["at"][11:16])} UTC</span>'
            f'{("<a class=tx href=" + EXPLORER + "/tx/" + esc(d["tx"]) + " target=_blank>View on BaseScan ↗</a>") if d.get("tx") else ""}</div></div>'
            for d in sorted(todays, key=lambda d: d["at"], reverse=True))
        md(f'<div class="card"><div class="ctitle">Decided today</div>{rows}</div>')


# ----------------------------------------------------------------------------- add payee dialog
def open_add_dialog(kind):
    is_people = kind == "payroll"
    threshold, cap = limits["approvalThresholdUsd"], limits["perPaymentCapUsd"]

    @st.dialog("Add a team member" if is_people else "Add a vendor")
    def _dialog():
        st.caption("Additions go live once the founder approves them in Approvals. Until then they're saved as pending and never paid.")
        name = st.text_input("Full name" if is_people else "Vendor name", placeholder="Jane Doe" if is_people else "Cloud hosting provider")
        if is_people:
            teams = sorted({group_of(p) for p in obligation(policy, "payroll")["payees"]})
            team = st.selectbox("Team", teams + ["New team"])
            group = st.text_input("Team name", placeholder="Data Science") if team == "New team" else team
        else:
            group = st.text_input("Category", placeholder="Infrastructure")
        address = st.text_input("Wallet address", placeholder="0x…")
        amount = st.number_input("Monthly amount (USDC)", min_value=0.0, step=500.0, format="%.0f")
        pre = st.checkbox(f"Pre-approve payments above the {money(threshold)} approval threshold",
                          help="Normally each payment at or above the threshold waits for the founder's sign-off.")
        st.caption(f"Payments can never exceed the {money(cap)} hard cap. Only the founder can change it in the signed policy.")
        if threshold <= amount <= cap and not pre:
            st.info(f"{money(amount)} is above the {money(threshold)} approval threshold, so each payment will wait for founder sign-off.")
        c1, c2 = st.columns(2)
        if c1.button("Cancel", use_container_width=True):
            st.rerun()
        if c2.button("Submit for signature", type="primary", use_container_width=True):
            current = read_json(PENDING_PATH, [])
            existing = {p["address"].lower() for ob in policy["obligations"] for p in ob["payees"]} | {p["address"].lower() for p in current}
            reserved = {TREASURY_ADDRESS.lower()} | {v["address"].lower() for v in policy.get("vaults", [])}
            errors = []
            if not name.strip():
                errors.append("Add a name.")
            if not (group or "").strip():
                errors.append("Add a team." if is_people else "Add a category.")
            if not ADDR_RE.match(address.strip()):
                errors.append("Enter a valid wallet address: 0x followed by 40 characters.")
            elif address.strip().lower() in existing:
                errors.append("That wallet is already a payee.")
            elif address.strip().lower() in reserved:
                errors.append("That's a treasury or vault address, not a payee.")
            if amount <= 0:
                errors.append("Enter a monthly amount above zero.")
            elif amount > cap:
                errors.append(f"{money(amount)} is above the {money(cap)} hard cap, so it can't be added here.")
            if errors:
                for e in errors:
                    st.error(e)
                return
            current.insert(0, {"kind": kind, "name": name.strip(), "group": group.strip(), "address": address.strip(),
                               "amount": float(amount), "preApprovedAboveThreshold": bool(pre), "requestedAt": now_iso(),
                               "status": "Awaiting founder signature"})
            write_json(PENDING_PATH, current)
            st.session_state.next_page = "Approvals"
            st.session_state.focus = f"add:{address.strip().lower()}"
            st.toast(f"{name.strip()} added. Approve it in Approvals to make it live.")
            st.rerun()

    _dialog()


def payee_table(ob_id):
    ob = obligation(policy, ob_id) or {"payees": []}
    rows = []
    for p in pending:
        if p.get("kind") == ob_id:
            rows.append({"Name": p["name"], "Group": p["group"], "Wallet": short(p["address"]), "Monthly": money(p["amount"]),
                         "Status": p.get("status", "Awaiting founder signature")})
    for p in ob["payees"]:
        rows.append({"Name": p["name"], "Group": group_of(p), "Wallet": short(p["address"]), "Monthly": money(p["amount"]),
                     "Status": "Active"})
    return pd.DataFrame(rows)


def render_obligation(ob_id):
    is_people = ob_id == "payroll"
    ob = obligation(policy, ob_id) or {"payees": [], "schedule": {"dayOfMonth": 1}}
    dom = ob["schedule"]["dayOfMonth"]
    head, btn = st.columns([4, 1.2])
    with head:
        md(f'<div class="sec">{"Payroll" if is_people else "Vendors"}</div><div class="muted">'
           f'{"Everyone" if is_people else "Services"} the agent pays on the {dom}{"st" if dom == 1 else "th"} of each month.</div>')
    with btn:
        st.write("")
        if st.button("Add team member" if is_people else "Add vendor", type="primary", use_container_width=True, key=f"add_{ob_id}"):
            open_add_dialog(ob_id)
    total = sum(p["amount"] for p in ob["payees"])
    waiting = [p for p in pending if p.get("kind") == ob_id]
    runs = df[(df["action"] == "PAY_BATCH") & df["obligation"].str.startswith(ob_id)]
    last = runs.iloc[0] if not runs.empty else None
    due = next_run(dom, today)
    md('<div class="kgrid">' + "".join([
        kpi("Monthly total", money(total), pill(f"{len(ob['payees'])} active", "ac"), "Paid in USDC",
            f"{len(waiting)} awaiting signature" if waiting else "No pending changes"),
        kpi("Next run", due.strftime("%b %d"), pill(f"In {(due - today).days} days"), "Runs automatically", "Within your signed policy"),
        kpi("Last run", money(last["amount"]) if last is not None else "—", status_pill(last) if last is not None else pill("Not run yet"),
            when(last) if last is not None else "Waiting for the first run", "One transaction for the whole batch"),
    ]) + "</div>")
    left, right = st.columns(2) if is_people else (st.container(), None)
    with left:
        body = (f'<div class="item"><div><div class="id">{esc(last.get("explanation") or "")}</div></div><div class="ir">{tx_html(last)}</div></div>'
                if last is not None else '<div class="muted">No runs yet.</div>')
        md(f'<div class="card"><div class="ctitle">Latest run</div>{body}</div>')
    if is_people:
        groups = {}
        for p in ob["payees"]:
            g = groups.setdefault(group_of(p), [0, 0.0])
            g[0] += 1
            g[1] += p["amount"]
        top = max((v[1] for v in groups.values()), default=1) or 1
        bars = "".join(f'<div style="margin:10px 0"><div style="display:flex;justify-content:space-between;font-size:13px">'
                       f'<span><b>{esc(g)}</b> · {c} people</span><span>{money(s)}</span></div>'
                       f'<div class="bar"><div style="width:{s / top * 100:.0f}%"></div></div></div>'
                       for g, (c, s) in sorted(groups.items(), key=lambda kv: -kv[1][1]))
        with right:
            md(f'<div class="card"><div class="ctitle">By team</div>{bars}</div>')
    table = payee_table(ob_id).rename(columns={"Group": "Team" if is_people else "Category", "Monthly": "Monthly (USDC)"})
    st.dataframe(table, use_container_width=True, hide_index=True, height=min(420, 38 + 35 * len(table)))
    if waiting:
        st.button(f"{len(waiting)} awaiting signature · open Approvals ›", key=f"to_ap_{ob_id}", on_click=nav, args=("Approvals",))
    if not is_people:
        inv = df[df["action"].isin(["PAY", "REQUEST_APPROVAL", "FOUNDER_APPROVAL", "FOUNDER_DENIAL"]) & ~df["status"].isin(BLOCKED)].head(8)
        md(f'<div class="card" style="margin-top:14px"><div class="ctitle">One-off invoices</div>'
           f'{"".join(activity_row(r, open_ids) for _, r in inv.iterrows()) or "<div class=muted>No one-off invoices yet.</div>"}</div>')


if page == "Payroll":
    render_obligation("payroll")
elif page == "Vendors":
    render_obligation("vendors")

elif page == "Treasury":
    md('<div class="sec">Treasury and yield</div><div class="muted">Where the money sits, and how spare cash is put to work.</div><br>')
    if state:
        liquid, vault = state["liquid_balance"], state["vault_balance"]
        total = liquid + vault or 1
        md(f'<div class="card"><div class="ctitle">Allocation</div><div class="alloc">'
           f'<div class="liq" style="width:{liquid / total * 100:.1f}%"></div>'
           f'<div class="vlt" style="left:{liquid / total * 100:.1f}%;width:{vault / total * 100:.1f}%"></div>'
           f'<div class="cap" style="left:{(1 - max_share) * 100:.1f}%"></div></div>'
           f'<div class="legend"><span><i class="sw" style="background:#0E0E14"></i>Wallet {money(liquid)}</span>'
           f'<span><i class="sw" style="background:#A855F7"></i>Vault {money(vault)}</span>'
           f'<span><i class="sw" style="background:#B42318"></i>Vault may not pass this line ({max_share:.0%} max)</span></div></div>')
    moves = df[df["action"].isin(["DEPOSIT_TO_VAULT", "EMERGENCY_EXIT"]) & (df["status"] == "CONFIRMED")]
    if not moves.empty:
        r = moves.iloc[0]
        is_exit = r["action"] == "EMERGENCY_EXIT"
        md(f'<div class="card"><div class="ctitle">{"Emergency exit" if is_exit else "Latest sweep to vault"}</div>'
           f'<div class="item"><div><div class="id">{esc(r.get("explanation") or "")}</div></div>'
           f'<div class="ir">{pill("Funds protected", "bad") if is_exit else pill("Earning", "ok")}{tx_html(r)}</div></div></div>')
    with st.container(border=True):
        render_yield_card(policy, state, "tr", "6 months")

elif page == "Security":
    blocked = df[df["status"].isin(BLOCKED)]
    proofs = blocked[(blocked["status"] == "FAILED") & blocked["tx_hash"].notna() & ~blocked["simulated"]]
    md('<div class="sec">Security</div><div class="muted">Every attempt the agent or the blockchain refused, and why.</div><br>')
    md('<div class="kgrid">' + "".join([
        kpi("Blocked attempts", str(len(blocked)), pill("Stopped", "ok"), "Refused by policy or contract", "No funds moved"),
        kpi("On-chain proofs", str(len(proofs)), pill("Reverted", "bad"), "Rejected by the Treasury contract", "Verifiable on BaseScan"),
        kpi("Hard cap", money(limits["perPaymentCapUsd"]), pill("Enforced on-chain", "ac"), "Per payment", "Only the founder can change it"),
    ]) + "</div>")
    md(f"""
    <div style="margin-top:10px"><div class="ctitle" style="font-size:18px">How every payment is checked</div>
    <div class="muted">Each request passes these four checks in order. Failing any one stops it before money moves.</div></div>
    <ol class="steps">
      <li><div class="st">Invoice text is treated as data</div><div class="sd">Memos and vendor messages are never read as instructions, so hidden commands in an invoice do nothing.</div>{pill("Checked by the agent")}</li>
      <li><div class="st">Payee must be on your allowlist</div><div class="sd">The agent can only pay wallets you approved. Anyone else is refused, even if the agent is fooled.</div>{pill("Enforced by the contract", "ac")}</li>
      <li><div class="st">Caps per payment and per day</div><div class="sd">Nothing over {money(limits['perPaymentCapUsd'])} in one payment or {money(limits['dailyPaymentCapUsd'])} in one day, whatever the agent decides.</div>{pill("Enforced by the contract", "ac")}</li>
      <li><div class="st">Only you change the rules</div><div class="sd">Limits, payees and vaults change only with your signature. The agent can't raise its own limits.</div>{pill("Signed by the founder", "ok")}</li>
    </ol>
    """)
    body = "".join(activity_row(r) for _, r in blocked.head(20).iterrows()) or '<div class="muted">No blocked attempts yet. Run the attack suite to generate evidence.</div>'
    md(f'<div class="card"><div class="ctitle">Blocked actions</div>{body}</div>')

elif page == "Audit log":
    head, btn = st.columns([4, 1.2])
    with head:
        md('<div class="sec">Decision log</div><div class="muted">Every decision the agent made, with the rule it followed and its transaction.</div>')
    with btn:
        st.write("")
        st.download_button("Download CSV", data=df[DB_COLUMNS].to_csv(index=False) if not df.empty else "",
                           file_name="audit_decisions.csv", mime="text/csv", use_container_width=True)
    if df.empty:
        st.caption("No decisions logged yet. Run engine.py to populate the log.")
    else:
        f1, f2 = st.columns(2)
        pick_a = f1.multiselect("Action", sorted(df["action"].unique()), format_func=lambda a: ACTIONS.get(a, a))
        pick_s = f2.multiselect("Status", sorted(df["status"].unique()), format_func=lambda s: STATUS.get(s, (s,))[0])
        v = df.copy()
        if pick_a:
            v = v[v["action"].isin(pick_a)]
        if pick_s:
            v = v[v["status"].isin(pick_s)]
        table = pd.DataFrame({
            "Time": v["ts"].dt.strftime("%b %d, %H:%M UTC"),
            "Action": v["action"].map(lambda a: ACTIONS.get(a, a)),
            "Tier": v["tier"],
            "Amount": v["amount"].map(money),
            "Status": [("Simulated test run" if s else STATUS.get(x, (x,))[0]) for s, x in zip(v["simulated"], v["status"])],
            "Transaction": [None if s else tx_url(r) for s, (_, r) in zip(v["simulated"], v.iterrows())],
            "Explanation": v["explanation"],
        })
        st.dataframe(table, use_container_width=True, hide_index=True, column_config={
            "Transaction": st.column_config.LinkColumn("Transaction", display_text="View on BaseScan ↗"),
            "Explanation": st.column_config.TextColumn("Explanation", width="large"),
        })
