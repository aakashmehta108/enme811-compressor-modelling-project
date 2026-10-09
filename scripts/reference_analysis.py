"""
Python/CoolProp reference analysis for the ENME811 compressor package.

This script mirrors the MATLAB workflow and produces the numerical values,
CSV outputs and figures used in the technical report.  It is a verification
reference; the submitted modelling package is the MATLAB code in ../matlab.
"""
from __future__ import annotations

import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from CoolProp.CoolProp import PropsSI

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "compressor_performance_data.csv"
RESULTS = ROOT / "results"
FIGURES = RESULTS / "figures"
REPORT_FIGURES = ROOT / "report" / "figures"
REF = "R134a"
SUPERHEAT_K = 5.0
BORE_M, STROKE_M, CYLINDERS = 0.070, 0.0497, 6
VD = CYLINDERS * np.pi / 4 * BORE_M**2 * STROKE_M

plt.rcParams.update({
    "font.size": 10,
    "axes.titlesize": 12,
    "axes.labelsize": 10.5,
    "legend.fontsize": 8.5,
    "figure.dpi": 160,
    "savefig.dpi": 220,
    "axes.grid": True,
    "grid.alpha": 0.28,
})


def props(te_c: float, tc_c: float) -> dict[str, float]:
    p_suc = PropsSI("P", "T", te_c + 273.15, "Q", 0, REF)
    p_dis = PropsSI("P", "T", tc_c + 273.15, "Q", 0, REF)
    t_suc = te_c + 273.15 + SUPERHEAT_K
    rho = PropsSI("D", "P", p_suc, "T", t_suc, REF)
    h1 = PropsSI("H", "P", p_suc, "T", t_suc, REF)
    s1 = PropsSI("S", "P", p_suc, "T", t_suc, REF)
    h2s = PropsSI("H", "P", p_dis, "S", s1, REF)
    return {
        "P_suc_Pa": p_suc,
        "P_dis_Pa": p_dis,
        "beta": p_dis / p_suc,
        "rho_suc": rho,
        "v_suc": 1.0 / rho,
        "h1": h1,
        "s1": s1,
        "h2is": h2s,
    }


def design(beta: np.ndarray, fn: np.ndarray, form: str) -> np.ndarray:
    ones = np.ones_like(beta, dtype=float)
    if form == "A":
        return np.column_stack([ones, beta, beta**2])
    if form == "B":
        return np.column_stack([ones, beta, beta**2, fn, fn**2])
    if form == "C":
        return np.column_stack([ones, beta, beta**2, fn, beta * fn, fn**2])
    raise ValueError(form)


def fit_stats(X: np.ndarray, y: np.ndarray) -> tuple[np.ndarray, np.ndarray, dict[str, float]]:
    coeff, *_ = np.linalg.lstsq(X, y, rcond=None)
    yhat = X @ coeff
    resid = y - yhat
    rmse = float(np.sqrt(np.mean(resid**2)))
    ss_res = float(np.sum(resid**2))
    ss_tot = float(np.sum((y - np.mean(y)) ** 2))
    r2 = 1.0 - ss_res / ss_tot
    p = X.shape[1] - 1
    adj = 1.0 - (1.0 - r2) * (len(y) - 1) / max(len(y) - p - 1, 1)
    return coeff, yhat, {"R2": float(r2), "adjR2": float(adj), "RMSE": rmse}


def predict_rows(frame: pd.DataFrame, coeff_v: np.ndarray, coeff_is: np.ndarray) -> pd.DataFrame:
    out = []
    for _, r in frame.iterrows():
        st = props(float(r.T_evap_C), float(r.T_cond_C))
        fn = float(r.freq_Hz) / 50.0
        x = design(np.array([st["beta"]]), np.array([fn]), "C")[0]
        ev = float(x @ coeff_v)
        ei = float(x @ coeff_is)
        m_dot = ev * VD * float(r.freq_Hz) / st["v_suc"]
        w_kw = m_dot * (st["h2is"] - st["h1"]) / ei / 1000.0
        h2 = st["h1"] + (st["h2is"] - st["h1"]) / ei
        t_dis = PropsSI("T", "P", st["P_dis_Pa"], "H", h2, REF) - 273.15
        out.append({
            "eta_v_pred": ev,
            "eta_is_pred": ei,
            "m_dot_pred_kg_s": m_dot,
            "W_pred_kW": w_kw,
            "T_dis_pred_C": t_dis,
        })
    return pd.DataFrame(out, index=frame.index)


def error_metrics(ref: np.ndarray, pred: np.ndarray) -> dict[str, float]:
    pct = np.abs(pred - ref) / np.abs(ref) * 100
    return {
        "MAPE_pct": float(np.mean(pct)),
        "RMSE": float(np.sqrt(np.mean((pred - ref) ** 2))),
        "MaxAPE_pct": float(np.max(pct)),
    }


def main() -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    FIGURES.mkdir(parents=True, exist_ok=True)
    REPORT_FIGURES.mkdir(parents=True, exist_ok=True)

    raw = pd.read_csv(DATA)
    calc_rows = []
    for _, r in raw.iterrows():
        st = props(float(r.T_evap_C), float(r.T_cond_C))
        eta_v = float(r.m_dot_kg_s) * st["v_suc"] / (VD * float(r.freq_Hz))
        eta_is = float(r.m_dot_kg_s) * (st["h2is"] - st["h1"]) / (float(r.W_el_kW) * 1000)
        h2_actual = st["h1"] + float(r.W_el_kW) * 1000 / float(r.m_dot_kg_s)
        t_dis_calc = PropsSI("T", "P", st["P_dis_Pa"], "H", h2_actual, REF) - 273.15
        calc_rows.append({
            **st,
            "eta_v_calc": eta_v,
            "eta_is_calc": eta_is,
            "T_dis_from_power_C": t_dis_calc,
            "fn": float(r.freq_Hz) / 50.0,
        })
    calc = pd.DataFrame(calc_rows)
    df = pd.concat([raw.reset_index(drop=True), calc], axis=1)

    fitting = df[df.dataset == "Fitting"].copy()
    validation = df[df.dataset == "Validation"].copy()

    candidate_rows = []
    fitted = {}
    for form in ["A", "B", "C"]:
        X = design(fitting.beta.to_numpy(), fitting.fn.to_numpy(), form)
        cv, _, sv = fit_stats(X, fitting.eta_v_calc.to_numpy())
        ci, _, si = fit_stats(X, fitting.eta_is_calc.to_numpy())
        fitted[form] = (cv, ci, sv, si)
        candidate_rows.append({
            "model": form,
            "terms": {"A": "1, beta, beta^2", "B": "1, beta, beta^2, fn, fn^2", "C": "1, beta, beta^2, fn, beta*fn, fn^2"}[form],
            "eta_v_R2": sv["R2"], "eta_v_adjR2": sv["adjR2"], "eta_v_RMSE": sv["RMSE"],
            "eta_is_R2": si["R2"], "eta_is_adjR2": si["adjR2"], "eta_is_RMSE": si["RMSE"],
        })
    candidates = pd.DataFrame(candidate_rows)
    candidates.to_csv(RESULTS / "candidate_model_comparison.csv", index=False)

    coeff_v, coeff_is, stats_v, stats_is = fitted["C"]

    # One-dimensional fixed-frequency fits on fitting frequencies.
    one_d_rows = []
    for freq in sorted(fitting.freq_Hz.unique()):
        sub = fitting[fitting.freq_Hz == freq]
        X = design(sub.beta.to_numpy(), sub.fn.to_numpy(), "A")
        cv, _, sv = fit_stats(X, sub.eta_v_calc.to_numpy())
        ci, _, si = fit_stats(X, sub.eta_is_calc.to_numpy())
        one_d_rows.append({
            "freq_Hz": float(freq),
            "eta_v_c0": cv[0], "eta_v_c1_beta": cv[1], "eta_v_c2_beta2": cv[2],
            "eta_v_R2": sv["R2"], "eta_v_RMSE": sv["RMSE"],
            "eta_is_c0": ci[0], "eta_is_c1_beta": ci[1], "eta_is_c2_beta2": ci[2],
            "eta_is_R2": si["R2"], "eta_is_RMSE": si["RMSE"],
            "n_points": len(sub),
        })
    one_d = pd.DataFrame(one_d_rows)
    one_d.to_csv(RESULTS / "one_dimensional_fits.csv", index=False)

    terms = ["constant", "beta", "beta^2", "fn", "beta*fn", "fn^2"]
    coeff_table = pd.DataFrame({
        "Term": terms,
        "eta_v_coefficient": coeff_v,
        "eta_is_coefficient": coeff_is,
    })
    coeff_table.to_csv(RESULTS / "regression_coefficients.csv", index=False)

    pred_all = predict_rows(df, coeff_v, coeff_is)
    calculated = pd.concat([df.reset_index(drop=True), pred_all.reset_index(drop=True)], axis=1)
    calculated["m_dot_error_pct"] = 100 * (calculated.m_dot_pred_kg_s - calculated.m_dot_kg_s) / calculated.m_dot_kg_s
    calculated["W_error_pct"] = 100 * (calculated.W_pred_kW - calculated.W_el_kW) / calculated.W_el_kW
    calculated["T_dis_error_C"] = calculated.T_dis_pred_C - calculated.T_dis_C
    calculated.to_csv(RESULTS / "calculated_variables.csv", index=False)

    val_pred = calculated[calculated.dataset == "Validation"].copy()
    val_pred.to_csv(RESULTS / "validation_results.csv", index=False)

    m_metrics = error_metrics(val_pred.m_dot_kg_s.to_numpy(), val_pred.m_dot_pred_kg_s.to_numpy())
    w_metrics = error_metrics(val_pred.W_el_kW.to_numpy(), val_pred.W_pred_kW.to_numpy())
    t_metrics = {
        "MAE_C": float(np.mean(np.abs(val_pred.T_dis_pred_C - val_pred.T_dis_C))),
        "RMSE_C": float(np.sqrt(np.mean((val_pred.T_dis_pred_C - val_pred.T_dis_C) ** 2))),
        "MaxAE_C": float(np.max(np.abs(val_pred.T_dis_pred_C - val_pred.T_dis_C))),
    }

    new_cases = pd.DataFrame({
        "T_evap_C": [-12, -2, 7, 3],
        "T_cond_C": [40, 50, 45, 55],
        "freq_Hz": [38, 68, 52, 75],
    })
    new_pred = predict_rows(new_cases, coeff_v, coeff_is)
    new_betas = [props(te, tc)["beta"] for te, tc in zip(new_cases.T_evap_C, new_cases.T_cond_C)]
    new_out = new_cases.copy()
    new_out.insert(3, "beta", new_betas)
    new_out = pd.concat([new_out, new_pred], axis=1)
    new_out.to_csv(RESULTS / "new_case_predictions.csv", index=False)

    # Client design point: R134a, Te = -10 degC, 5 K superheat, rated 50 Hz,
    # design condensing temperature 45 degC. Cooling capacity uses the
    # refrigerating effect qL = h1 - h_f(T_cond) (no subcooling specified).
    design_case = pd.DataFrame({"T_evap_C": [-10.0], "T_cond_C": [45.0], "freq_Hz": [50.0]})
    design_pred = predict_rows(design_case, coeff_v, coeff_is)
    d_state = props(-10.0, 45.0)
    h_liquid = PropsSI("H", "T", 45.0 + 273.15, "Q", 0, REF)
    q_l = (d_state["h1"] - h_liquid) / 1000.0  # kJ/kg
    m_design = float(design_pred.m_dot_pred_kg_s.iloc[0])
    w_design = float(design_pred.W_pred_kW.iloc[0])
    q_design = m_design * q_l
    design_point = {
        "T_evap_C": -10.0,
        "T_cond_C_design": 45.0,
        "freq_Hz": 50.0,
        "superheat_K": SUPERHEAT_K,
        "beta": d_state["beta"],
        "P_suc_bar": d_state["P_suc_Pa"] / 1e5,
        "P_dis_bar": d_state["P_dis_Pa"] / 1e5,
        "rho_suc_kg_m3": d_state["rho_suc"],
        "h1_kJ_kg": d_state["h1"] / 1000.0,
        "h_f_cond_kJ_kg": h_liquid / 1000.0,
        "refrigerating_effect_kJ_kg": q_l,
        "required_m_dot_for_50kW_kg_s": 50.0 / q_l,
        "eta_v_pred": float(design_pred.eta_v_pred.iloc[0]),
        "eta_is_pred": float(design_pred.eta_is_pred.iloc[0]),
        "m_dot_pred_kg_s": m_design,
        "W_pred_kW": w_design,
        "T_dis_pred_C": float(design_pred.T_dis_pred_C.iloc[0]),
        "cooling_capacity_pred_kW": q_design,
        "COP_cooling_pred": q_design / w_design,
    }
    pd.DataFrame([design_point]).to_csv(RESULTS / "design_point.csv", index=False)

    summary = {
        "Vd_cm3_rev": VD * 1e6,
        "n_fitting": int(len(fitting)),
        "n_validation": int(len(validation)),
        "beta_range": [float(df.beta.min()), float(df.beta.max())],
        "eta_v_range": [float(df.eta_v_calc.min()), float(df.eta_v_calc.max())],
        "eta_is_range": [float(df.eta_is_calc.min()), float(df.eta_is_calc.max())],
        "m_dot_range_kg_s": [float(df.m_dot_kg_s.min()), float(df.m_dot_kg_s.max())],
        "W_range_kW": [float(df.W_el_kW.min()), float(df.W_el_kW.max())],
        "T_dis_range_C": [float(df.T_dis_C.min()), float(df.T_dis_C.max())],
        "coeff_eta_v": coeff_v.tolist(),
        "coeff_eta_is": coeff_is.tolist(),
        "eta_v_fit": stats_v,
        "eta_is_fit": stats_is,
        "validation_mass_flow": m_metrics,
        "validation_power": w_metrics,
        "validation_T_dis": t_metrics,
        "design_point": design_point,
    }
    (RESULTS / "report_values.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")

    make_figures(df, val_pred, coeff_v, coeff_is)
    print(json.dumps(summary, indent=2))


def save(fig: plt.Figure, name: str) -> None:
    fig.tight_layout()
    for folder in [FIGURES, REPORT_FIGURES]:
        fig.savefig(folder / name, bbox_inches="tight")
    plt.close(fig)


def make_figures(df: pd.DataFrame, val: pd.DataFrame, coeff_v: np.ndarray, coeff_is: np.ndarray) -> None:
    frequencies = sorted(df.freq_Hz.unique())
    cmap = plt.get_cmap("viridis")
    colors = {f: cmap(i / max(len(frequencies) - 1, 1)) for i, f in enumerate(frequencies)}

    for response, coeff, ylabel, filename, title in [
        ("eta_v_calc", coeff_v, r"Volumetric efficiency $\eta_v$ [-]", "eta_v_vs_beta.png", "Volumetric efficiency vs pressure ratio"),
        ("eta_is_calc", coeff_is, r"Isentropic efficiency $\eta_{is}$ [-]", "eta_is_vs_beta.png", "Isentropic efficiency vs pressure ratio"),
    ]:
        fig, ax = plt.subplots(figsize=(7.4, 4.8))
        for freq in frequencies:
            part = df[df.freq_Hz == freq]
            fit_part = part[part.dataset == "Fitting"]
            val_part = part[part.dataset == "Validation"]
            if len(fit_part):
                ax.scatter(fit_part.beta, fit_part[response], s=42, color=colors[freq], edgecolor="white", linewidth=0.5, label=f"{freq:g} Hz fit")
            if len(val_part):
                ax.scatter(val_part.beta, val_part[response], s=58, marker="x", color=colors[freq], linewidth=1.4, label=f"{freq:g} Hz validation")
        b = np.linspace(df.beta.min(), df.beta.max(), 140)
        fn45 = np.full_like(b, 45 / 50)
        y = design(b, fn45, "C") @ coeff
        ax.plot(b, y, color="black", lw=2, label="2-D model at 45 Hz")
        ax.set_xlabel(r"Pressure ratio $\beta=P_{dis}/P_{suc}$ [-]")
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        ax.legend(ncol=3, frameon=True)
        save(fig, filename)

    # Model surfaces over the fitted/validated envelope.
    b_grid = np.linspace(df.beta.min(), df.beta.max(), 80)
    f_grid = np.linspace(30, 75, 80)
    BB, FF = np.meshgrid(b_grid, f_grid)
    for coeff, title, filename, label in [
        (coeff_v, r"2-D volumetric-efficiency surface", "eta_v_surface.png", r"$\eta_v$"),
        (coeff_is, r"2-D isentropic-efficiency surface", "eta_is_surface.png", r"$\eta_{is}$"),
    ]:
        Z = design(BB.ravel(), (FF.ravel() / 50), "C") @ coeff
        Z = Z.reshape(BB.shape)
        fig, ax = plt.subplots(figsize=(7.2, 4.8))
        cs = ax.contourf(BB, FF, Z, levels=18, cmap="viridis")
        cbar = fig.colorbar(cs, ax=ax)
        cbar.set_label(label)
        ax.set_xlabel(r"Pressure ratio $\beta$ [-]")
        ax.set_ylabel("Frequency [Hz]")
        ax.set_title(title)
        save(fig, filename)

    parity_specs = [
        ("m_dot_kg_s", "m_dot_pred_kg_s", 1000, "g/s", "parity_mass_flow.png", "Mass-flow parity (independent validation)"),
        ("W_el_kW", "W_pred_kW", 1, "kW", "parity_power.png", "Power-input parity (independent validation)"),
        ("T_dis_C", "T_dis_pred_C", 1, "°C", "parity_discharge_temperature.png", "Discharge-temperature parity (independent validation)"),
    ]
    for ref_col, pred_col, scale, unit, filename, title in parity_specs:
        ref = val[ref_col].to_numpy() * scale
        pred = val[pred_col].to_numpy() * scale
        fig, ax = plt.subplots(figsize=(5.4, 5.0))
        ax.scatter(ref, pred, s=48, color="#176B87", edgecolor="white", linewidth=0.6)
        lo = min(ref.min(), pred.min()); hi = max(ref.max(), pred.max())
        pad = 0.06 * (hi - lo)
        ax.plot([lo-pad, hi+pad], [lo-pad, hi+pad], "k--", lw=1.2, label="Perfect prediction")
        ax.set_xlim(lo-pad, hi+pad); ax.set_ylim(lo-pad, hi+pad)
        ax.set_aspect("equal", adjustable="box")
        ax.set_xlabel(f"Reference [{unit}]")
        ax.set_ylabel(f"Predicted [{unit}]")
        ax.set_title(title)
        ax.legend()
        save(fig, filename)


if __name__ == "__main__":
    main()
