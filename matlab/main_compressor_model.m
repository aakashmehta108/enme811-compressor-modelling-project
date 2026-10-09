%% ENME811 Compressor Modelling Project
% Variable-speed hermetic reciprocating compressor using R134a.
%
% Workflow:
%   1. Load the documented performance table (Fitting/Validation split).
%   2. Calculate CoolProp refrigerant states and efficiencies.
%   3. Fit 1-D fixed-frequency and 2-D pressure-ratio/frequency models.
%   4. Predict mass flow, power input and discharge temperature.
%   5. Validate against independent Validation rows and save figures/tables.
%
% Run this script from MATLAB's Editor (F5). CoolProp must be installed in
% the Python environment used by MATLAB; see README.md.

clear; clc; close all;

%% 0. Project paths and compressor specification
scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
dataFile = fullfile(scriptDir, 'data', 'compressor_performance_data.csv');
resultsDir = fullfile(scriptDir, 'results');
if ~isfolder(resultsDir)
    mkdir(resultsDir);
end

fluid = 'R134a';
superheatK = 5;                  % suction superheat [K] (client-supplied)
bore_m = 0.070;                  % bore [m]
stroke_m = 0.0497;               % stroke [m]
cylinders = 6;
Vd = cylinders * pi/4 * bore_m^2 * stroke_m;  % displacement [m3/rev]

fprintf('Selected compressor: variable-speed hermetic reciprocating\n');
fprintf('Refrigerant: %s; displacement: %.3f cm3/rev; superheat: %.1f K\n', ...
    fluid, Vd*1e6, superheatK);

%% 1. Data preparation
data = loadCompressorData(dataFile);

%% 2. Property and efficiency calculations
res = calcEfficiencies(data, fluid, superheatK, Vd);

%% 3. Regression models (Fitting rows only)
models = fitEfficiencyModels(data, res);
disp('Candidate model comparison (fitting rows only):');
disp(models.comparison);
writetable(models.comparison, fullfile(resultsDir, 'candidate_model_comparison.csv'));

terms = ["constant"; "beta"; "beta^2"; "fn"; "beta*fn"; "fn^2"];
coefficientTable = table(terms, models.coeffV, models.coeffIs, ...
    'VariableNames', {'Term','eta_v_coefficient','eta_is_coefficient'});
writetable(coefficientTable, fullfile(resultsDir, 'regression_coefficients.csv'));

oneD = models.oneD;
oneDTable = table(oneD.frequencies_Hz, oneD.coeffV(:,1), oneD.coeffV(:,2), ...
    oneD.coeffV(:,3), oneD.R2V, oneD.RMSEV, oneD.coeffIs(:,1), ...
    oneD.coeffIs(:,2), oneD.coeffIs(:,3), oneD.R2Is, oneD.RMSEIs, ...
    'VariableNames', {'freq_Hz','eta_v_c0','eta_v_c1_beta','eta_v_c2_beta2', ...
    'eta_v_R2','eta_v_RMSE','eta_is_c0','eta_is_c1_beta','eta_is_c2_beta2', ...
    'eta_is_R2','eta_is_RMSE'});
writetable(oneDTable, fullfile(resultsDir, 'one_dimensional_fits.csv'));
disp('One-dimensional fixed-frequency fits:');
disp(oneDTable);

%% 4. Calculated-variable table for every supplied row
[m_all, W_all, T_all, eta_v_all, eta_is_all, beta_all, rho_all] = ...
    predictPerformance(data.T_evap, data.T_cond, data.f, models, ...
    fluid, superheatK, Vd);

calculated = data.T;
calculated.beta = beta_all;
calculated.rho_suc_kg_m3 = rho_all;
calculated.v_suc_m3_kg = 1 ./ rho_all;
calculated.h1_kJ_kg = res.h1 / 1000;
calculated.s1_kJ_kgK = res.s1 / 1000;
calculated.h2is_kJ_kg = res.h2is / 1000;
calculated.eta_v_calculated = res.eta_v;
calculated.eta_is_calculated = res.eta_is;
calculated.eta_v_predicted = eta_v_all;
calculated.eta_is_predicted = eta_is_all;
calculated.m_dot_pred_kg_s = m_all;
calculated.W_pred_kW = W_all;
calculated.T_dis_pred_C = T_all;
writetable(calculated, fullfile(resultsDir, 'calculated_variables.csv'));

%% 5. Predictions at representative new operating points
Te_new = [-12; -2; 7; 3];
Tc_new = [40; 50; 45; 55];
f_new = [38; 68; 52; 75];
[m_new, W_new, T_new, eta_v_new, eta_is_new, beta_new, ~] = ...
    predictPerformance(Te_new, Tc_new, f_new, models, fluid, superheatK, Vd);

newCases = table(Te_new, Tc_new, f_new, beta_new, eta_v_new, eta_is_new, ...
    m_new, W_new, T_new, 'VariableNames', {'T_evap_C','T_cond_C','freq_Hz', ...
    'beta','eta_v','eta_is','m_dot_kg_s','W_el_kW','T_dis_C'});
writetable(newCases, fullfile(resultsDir, 'new_case_predictions.csv'));
fprintf('\nPredictions at representative new operating points:\n');
disp(newCases);

%% 6. Client design-point check
% Supplied duty: R134a, 50 kW cooling at T_evap = -10 degC with 5 K suction
% superheat. Design condensing temperature 45 degC, rated frequency 50 Hz.
% Cooling capacity Q = m_dot * (h1 - h_f(T_cond)); no subcooling specified.
Te_d = -10; Tc_d = 45; f_d = 50;
[m_d, W_d, T_d, ev_d, ei_d, beta_d, ~] = predictPerformance(Te_d, Tc_d, f_d, ...
    models, fluid, superheatK, Vd);
P_suc_d = getRefrigerantProp('P', 'T', Te_d + 273.15, 'Q', 0, fluid);
h1_d = getRefrigerantProp('H', 'P', P_suc_d, 'T', Te_d + 273.15 + superheatK, fluid);
hf_d = getRefrigerantProp('H', 'T', Tc_d + 273.15, 'Q', 0, fluid);
Q_d = m_d * (h1_d - hf_d) / 1000;   % kW
fprintf('\nDesign point (Te=-10 C, Tc=45 C, f=50 Hz, superheat=5 K):\n');
fprintf('beta=%.3f, eta_v=%.4f, eta_is=%.4f, m_dot=%.4f kg/s, W=%.3f kW, T_dis=%.2f C\n', ...
    beta_d, ev_d, ei_d, m_d, W_d, T_d);
fprintf('Predicted cooling capacity = %.2f kW (target 50 kW), COP = %.3f\n', Q_d, Q_d / W_d);

%% 7. Independent validation and figures
metrics = validateModel(data, res, models, fluid, superheatK, Vd, resultsDir);

fprintf('\nOutputs written to: %s\n', resultsDir);
fprintf('Done.\n');
