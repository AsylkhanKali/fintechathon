import streamlit as st
import pandas as pd
import sqlite3
import os
from datetime import date, timedelta
import altair as alt

# Import live telemetry functions from your working engine
from engine import fetch_onchain_state, load_and_hash_policy
from engine_logic import calculate_obligations_and_buffer

# Page Configuration
st.set_page_config(page_title="Treasury Agent Demo", layout="wide")
st.title("🤖 Autonomous Treasury Agent Dashboard")

# --- 1. DATA FETCHING (LIVE FROM BLOCKCHAIN & DB) ---
@st.cache_data(ttl=3)  # Refresh every 3 seconds
def get_live_state():
    try:
        policy, p_hash = load_and_hash_policy("policy.json")
        state = fetch_onchain_state()
        _, req_buffer = calculate_obligations_and_buffer(policy)
        state["required_buffer"] = req_buffer
        state["max_vault_share"] = policy["limits"].get("maxVaultShareBps", 6000) / 10000.0
        return state
    except Exception as e:
        return None

@st.cache_data(ttl=3)
def load_decisions():
    if not os.path.exists("decisions.db"):
        return pd.DataFrame()
    conn = sqlite3.connect("decisions.db")
    df = pd.read_sql_query("SELECT * FROM decisions ORDER BY id DESC", conn)
    conn.close()
    return df

state = get_live_state()
df = load_decisions()

def get_latest_action(action_type, condition=None):
    """Helper to find the most recent specific action in the DB."""
    if df.empty:
        return None
    subset = df[df['action'] == action_type]
    if condition is not None:
        subset = subset[condition(subset)]
    return subset.iloc[0] if not subset.empty else None

# --- 2. LIVE ON-CHAIN TELEMETRY HEADER ---
if state:
    st.subheader("Live On-Chain Telemetry (Base Sepolia)")
    cols = st.columns(5)
    cols[0].metric("Liquid Balance", f"${state['liquid_balance']:,.2f}")
    cols[1].metric("Vault Balance", f"${state['vault_balance']:,.2f}")
    cols[2].metric("Total Assets", f"${state['liquid_balance'] + state['vault_balance']:,.2f}")
    cols[3].metric("Required Buffer", f"${state['required_buffer']:,.2f}")
    cols[4].metric("USDC Price", f"${state['token_price']:.4f}")
    st.divider()
else:
    st.warning("⚠️ Could not connect to Base Sepolia or load policy. Check RPC and .env.")

# --- 3. UI TABS ---
tab_payroll, tab_vendors, tab_yields, tab_audit = st.tabs([
    "💼 Payroll", "🏢 Vendors", "📈 Yield Management", "📜 Audit Log"
])

# --- TAB 1: PAYROLL ---
with tab_payroll:
    st.header("Payroll Execution")
    
    # Dynamically find the large payroll run (> $200k) and buffer restorations
    payroll_run = get_latest_action("PAY_BATCH", lambda s: s['amount'] > 200000)
    buffer_restoration = get_latest_action("WITHDRAW_FROM_VAULT")

    col1, col2 = st.columns(2)
    with col1:
        if payroll_run is not None:
            st.metric(label="Total Payroll Processed", value=f"${payroll_run['amount']:,.0f}", delta="- Deducted from Checking")
        else:
            st.metric(label="Total Payroll Processed", value="Waiting for tick...", delta="")
        
        req_buffer = f"${state['required_buffer']:,.0f}" if state else "N/A"
        st.metric(label="Target Safety Buffer", value=req_buffer)
        
    with col2:
        if payroll_run is not None:
            st.success(f"💼 **Agent Action:** {payroll_run['explanation']}")
            if payroll_run['tx_hash']:
                st.caption(f"🔗 [View on BaseScan](https://sepolia.basescan.org/tx/{payroll_run['tx_hash']})")

        if buffer_restoration is not None:
            st.warning(f"⚠️ **Buffer Alert & Restoration:** {buffer_restoration['explanation']}")
            if buffer_restoration['tx_hash']:
                st.caption(f"🔗 [View on BaseScan](https://sepolia.basescan.org/tx/{buffer_restoration['tx_hash']})")

# --- TAB 2: VENDORS ---
with tab_vendors:
    st.header("Vendor Payments & Invoices")
    
    # Find vendor batch runs (< $200k) and single ad-hoc invoices
    vendor_run = get_latest_action("PAY_BATCH", lambda s: s['amount'] < 200000)
    adhoc_invoices = df[df['action'].isin(['PAY', 'REQUEST_APPROVAL'])] if not df.empty else pd.DataFrame()

    col1, col2 = st.columns(2)
    with col1:
        if vendor_run is not None:
            st.metric(label="Total Vendor Payout", value=f"${vendor_run['amount']:,.0f}", delta="- Deducted from Checking")
        else:
            st.metric(label="Total Vendor Payout", value="Waiting for tick...")
            
        if not adhoc_invoices.empty:
            st.write("**Recent Ad-Hoc Invoices:**")
            st.dataframe(
                adhoc_invoices[['created_at', 'action', 'amount', 'status']], 
                use_container_width=True, hide_index=True
            )
    
    with col2:
        if vendor_run is not None:
            st.success(f"✅ **Agent Action:** {vendor_run['explanation']}")
            if vendor_run['tx_hash']:
                st.caption(f"🔗 [View on BaseScan](https://sepolia.basescan.org/tx/{vendor_run['tx_hash']})")

# --- TAB 3: YIELD MANAGEMENT ---
with tab_yields:
    st.header("Yield Management & Forecasting")
    
    deposit_run = get_latest_action("DEPOSIT_TO_VAULT")
    depeg_exit = get_latest_action("EMERGENCY_EXIT")
    
    if depeg_exit is not None:
        st.error(f"🚨 **EMERGENCY EXIT TRIGGERED:** {depeg_exit['explanation']}")
        if depeg_exit['tx_hash']:
            st.caption(f"🔗 [View on BaseScan](https://sepolia.basescan.org/tx/{depeg_exit['tx_hash']})")
    elif deposit_run is not None:
        st.success(f"📈 **Agent Action:** {deposit_run['explanation']}")
        if deposit_run['tx_hash']:
            st.caption(f"🔗 [View on BaseScan](https://sepolia.basescan.org/tx/{deposit_run['tx_hash']})")
    else:
        st.info("💡 Waiting for yield sweep telemetry...")
    
    st.divider()
    
    st.subheader("30-Day Yield Revenue Forecast")
    # Base the graph dynamically on real vault balance
    base_deposit = state['vault_balance'] if (state and state['vault_balance'] > 0) else 2400000
    daily_interest_rate = 0.05 / 365
    
    dates = [date.today() + timedelta(days=i) for i in range(31)]
    projected_balances = [base_deposit * (1 + daily_interest_rate * i) for i in range(31)]
    
    forecast_df = pd.DataFrame({
        "Date": dates,
        "Projected Vault Balance (USD)": projected_balances
    })
    
    chart = alt.Chart(forecast_df).mark_line(color="#2e86c1").encode(
        x=alt.X("Date:T", title=""),
        y=alt.Y("Projected Vault Balance (USD):Q", scale=alt.Scale(zero=False))
    )
    st.altair_chart(chart, use_container_width=True)

# --- TAB 4: AUDIT LOG ---
with tab_audit:
    col_a, col_b = st.columns([0.8, 0.2])
    col_a.header("Immutable Decision Feed")
    
    if not df.empty:
        col_b.download_button(
            label="⬇️ Download CSV",
            data=df.to_csv(index=False),
            file_name="audit_decisions.csv",
            mime="text/csv"
        )
        # Clean up columns for display
        display_df = df[['created_at', 'action', 'tier', 'amount', 'status', 'tx_hash', 'explanation']].copy()
        st.dataframe(display_df, use_container_width=True, hide_index=True)
    else:
        st.write("No agent decisions logged yet. Run engine.py to populate the ledger.")