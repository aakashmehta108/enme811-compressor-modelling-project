# MATLAB package: ENME811 compressor modelling

## Purpose

This package models a variable-speed hermetic reciprocating compressor using R134a. It loads a documented performance table, calculates refrigerant properties with CoolProp, derives volumetric and isentropic efficiencies, fits one-dimensional and two-dimensional polynomial regressions, predicts mass flow rate, electrical power and discharge temperature, and validates the predictions on rows that were not used for fitting.

## Selected case

- Refrigerant: R134a (client-supplied)
- Design duty: 50 kW cooling at evaporating temperature −10 °C (client-supplied)
- Suction superheat: 5 K (client-supplied)
- Design condensing temperature: 45 °C (documented design assumption; envelope 35–55 °C)
- Compressor type: variable-speed hermetic reciprocating
- Bore × stroke × cylinders: 70 mm × 49.7 mm × 6
- Displacement: 1,147.6 cm³/rev (calculated in the master script), sized so the fitted model predicts ≈50 kW at the design point (50 Hz)
- Frequency range in the supplied table: 30–75 Hz (1,800–4,500 rpm)
- Evaporating temperature range: −15 to 10 °C
- Condensing temperature range: 35 to 55 °C

## Data provenance

The client supplied the refrigerant, design cooling capacity, evaporating temperature and suction superheat listed above, but no manufacturer selection-software export. The CSV is therefore a documented representative manufacturer-style performance table, generated with CoolProp properties and physically realistic efficiency behaviour (see `../data/generate_dataset.py`). It is not represented as test data from a named commercial compressor. Replace the CSV with a genuine manufacturer export in the same column format to model a specific product; no MATLAB code changes are required.

## MATLAB and CoolProp setup

1. Open MATLAB and select the Python environment you will use, for example:

   ```matlab
   pyversion('C:\Path\To\python.exe')
   ```

   On macOS/Linux, use the appropriate Python executable path.

2. In a terminal using that same Python environment, install CoolProp:

   ```bash
   python -m pip install CoolProp
   ```

3. In MATLAB, check that CoolProp is visible:

   ```matlab
   py.CoolProp.CoolProp.PropsSI('P','T',278.15,'Q',0,'R134a')
   ```

4. Open `main_compressor_model.m` and press **F5**.

## Input data

`data/compressor_performance_data.csv` contains:

- `point_id`
- `dataset` (`Fitting` or `Validation`)
- evaporating and condensing temperatures
- frequency and shaft speed
- suction/discharge saturation pressures
- reference mass flow rate, electrical power and discharge temperature
- data-source description

Only `Fitting` rows estimate regression coefficients. `Validation` rows are reserved for independent error metrics.

## Outputs

Running the master script creates:

- `results/calculated_variables.csv`
- `results/regression_coefficients.csv`
- `results/candidate_model_comparison.csv`
- `results/one_dimensional_fits.csv`
- `results/new_case_predictions.csv`
- `results/validation_results.csv`
- efficiency and parity figures in `results/figures/`

## Function map

- `loadCompressorData.m` — import and data-quality checks
- `getRefrigerantProp.m` — CoolProp wrapper
- `calcEfficiencies.m` — state properties, pressure ratio and efficiencies
- `fitEfficiencyModels.m` — 1-D and 2-D polynomial regression
- `predictPerformance.m` — mass flow, power and discharge-temperature prediction
- `validateModel.m` — independent validation, error metrics and figures
