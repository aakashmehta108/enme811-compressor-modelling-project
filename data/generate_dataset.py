"""
Generate the documented performance dataset used by the ENME811 compressor
modelling package.

Important provenance note
-------------------------
The client-supplied design inputs for this assignment are: refrigerant
R134a, cooling capacity 50 kW, evaporating temperature -10 degC and suction
superheat 5 K.  No manufacturer selection-software export was supplied, so
this script creates a *representative manufacturer-style performance table*
for a variable-speed hermetic reciprocating compressor sized so that the
fitted model predicts approximately 50 kW of cooling at the design point
(T_evap = -10 degC, T_cond = 45 degC design condensing temperature,
f = 50 Hz, 5 K superheat).  Refrigerant properties are calculated with
CoolProp.  The mass-flow, power and discharge-temperature values are
generated from physically realistic efficiency maps and small random
perturbations.  They must not be described as measurements from a named
commercial compressor.  If a genuine manufacturer export becomes available,
it can replace the CSV without changing the MATLAB analysis code.
"""
from pathlib import Path
import numpy as np
import pandas as pd
from CoolProp.CoolProp import PropsSI

ROOT = Path(__file__).resolve().parents[1]
REF = "R134a"
SUPERHEAT_K = 5.0
BORE_M = 0.070
STROKE_M = 0.0497
CYLINDERS = 6
VD_M3_REV = CYLINDERS * np.pi / 4 * BORE_M**2 * STROKE_M
RNG = np.random.default_rng(8112026)


def efficiencies(beta: float, freq_hz: float) -> tuple[float, float]:
    """Physically realistic latent efficiency maps used only for synthesis."""
    fn = freq_hz / 50.0
    eta_v = (
        0.940
        - 0.038 * beta
        - 0.0015 * beta**2
        + 0.018 * (fn - 1.0)
        - 0.030 * (fn - 1.0) ** 2
    )
    eta_is = (
        0.760
        - 0.018 * (beta - 3.5)
        - 0.0040 * (beta - 3.5) ** 2
        + 0.006 * (fn - 1.0)
        - 0.025 * (fn - 1.0) ** 2
    )
    return float(np.clip(eta_v, 0.35, 0.92)), float(np.clip(eta_is, 0.35, 0.85))


def make_point(point_id: int, dataset: str, te: float, tc: float, freq: float) -> dict:
    p_suc = PropsSI("P", "T", te + 273.15, "Q", 0, REF)
    p_dis = PropsSI("P", "T", tc + 273.15, "Q", 0, REF)
    t_suc = te + 273.15 + SUPERHEAT_K
    rho_suc = PropsSI("D", "P", p_suc, "T", t_suc, REF)
    v_suc = 1.0 / rho_suc
    h1 = PropsSI("H", "P", p_suc, "T", t_suc, REF)
    s1 = PropsSI("S", "P", p_suc, "T", t_suc, REF)
    h2s = PropsSI("H", "P", p_dis, "S", s1, REF)
    beta = p_dis / p_suc

    eta_v_true, eta_is_true = efficiencies(beta, freq)
    m_dot = eta_v_true * VD_M3_REV * freq / v_suc
    w_kw = m_dot * (h2s - h1) / eta_is_true / 1000.0
    h2 = h1 + (h2s - h1) / eta_is_true
    t_dis = PropsSI("T", "P", p_dis, "H", h2, REF) - 273.15

    # Independent-looking scatter.  The MATLAB model does not use these
    # latent efficiencies; it recalculates efficiencies from m_dot and W.
    m_dot_obs = m_dot * (1.0 + RNG.normal(0.0, 0.007))
    w_obs = w_kw * (1.0 + RNG.normal(0.0, 0.009))
    t_dis_obs = t_dis + RNG.normal(0.0, 1.0)

    return {
        "point_id": point_id,
        "dataset": dataset,
        "T_evap_C": te,
        "T_cond_C": tc,
        "freq_Hz": freq,
        "speed_rpm": 60.0 * freq,
        "P_suc_bar": p_suc / 1e5,
        "P_dis_bar": p_dis / 1e5,
        "m_dot_kg_s": m_dot_obs,
        "W_el_kW": w_obs,
        "T_dis_C": t_dis_obs,
        "data_source": "Representative manufacturer-style table; CoolProp R134a properties",
    }


def main() -> None:
    rows = []
    pid = 1
    for te in [-15, -10, -5, 0, 5, 10]:
        for tc in [35, 45, 55]:
            for freq in [30, 45, 60]:
                rows.append(make_point(pid, "Fitting", te, tc, freq))
                pid += 1

    # Independent validation: an unseen frequency plane plus off-grid points.
    for te in [-15, -10, -5, 0, 5, 10]:
        for tc in [35, 45, 55]:
            rows.append(make_point(pid, "Validation", te, tc, 75))
            pid += 1

    off_grid = [
        (-12, 40, 38), (-12, 50, 68), (-7, 40, 68), (-7, 50, 38),
        (-2, 40, 38), (-2, 50, 68), (3, 40, 68), (3, 50, 38),
        (8, 40, 38), (8, 50, 68), (-12, 40, 68), (8, 50, 38),
    ]
    for te, tc, freq in off_grid:
        rows.append(make_point(pid, "Validation", te, tc, freq))
        pid += 1

    df = pd.DataFrame(rows)
    for path in [ROOT / "data" / "compressor_performance_data.csv",
                 ROOT / "matlab" / "data" / "compressor_performance_data.csv"]:
        path.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(path, index=False)
    print(f"Wrote {len(df)} points; Vd = {VD_M3_REV * 1e6:.3f} cm3/rev")
    print(df.groupby('dataset').size().to_string())


if __name__ == "__main__":
    main()
