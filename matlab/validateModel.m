function metrics = validateModel(data, res, models, fluid, superheatK, Vd, resultsDir)
%VALIDATEMODEL Validate the fitted model on independent Validation rows.
%
% The Validation rows were excluded from fitEfficiencyModels. Predicted
% mass flow, power and discharge temperature are compared with the
% tabulated reference values. Figures and validation_results.csv are
% written to resultsDir.

if ~isfolder(resultsDir)
    mkdir(resultsDir);
end
figDir = fullfile(resultsDir, 'figures');
if ~isfolder(figDir)
    mkdir(figDir);
end

val = data.isValidation;
[m_pred, W_pred, T_pred, eta_v_pred, eta_is_pred, beta_pred, ~] = ...
    predictPerformance(data.T_evap(val), data.T_cond(val), data.f(val), ...
    models, fluid, superheatK, Vd);

m_ref = data.m_dot(val);
W_ref = data.W_el(val);
T_ref = data.T_dis_ref(val);

metrics = struct();
[metrics.m_MAPE, metrics.m_RMSE, metrics.m_MaxAPE] = errorMetrics(m_ref, m_pred);
[metrics.W_MAPE, metrics.W_RMSE, metrics.W_MaxAPE] = errorMetrics(W_ref, W_pred);
metrics.T_MAE_C = mean(abs(T_pred - T_ref));
metrics.T_RMSE_C = sqrt(mean((T_pred - T_ref).^2));
metrics.T_MaxAE_C = max(abs(T_pred - T_ref));
metrics.nValidation = sum(val);

fprintf('\nIndependent validation (%d points):\n', metrics.nValidation);
fprintf('  Mass flow: MAPE = %.2f %%, RMSE = %.5f kg/s, max APE = %.2f %%\n', ...
    metrics.m_MAPE, metrics.m_RMSE, metrics.m_MaxAPE);
fprintf('  Power:     MAPE = %.2f %%, RMSE = %.4f kW, max APE = %.2f %%\n', ...
    metrics.W_MAPE, metrics.W_RMSE, metrics.W_MaxAPE);
fprintf('  Discharge temperature: MAE = %.2f degC, RMSE = %.2f degC, max AE = %.2f degC\n', ...
    metrics.T_MAE_C, metrics.T_RMSE_C, metrics.T_MaxAE_C);

validationTable = table(data.point_id(val), data.T_evap(val), data.T_cond(val), ...
    data.f(val), beta_pred, res.eta_v(val), eta_v_pred, res.eta_is(val), eta_is_pred, ...
    m_ref, m_pred, 100*(m_pred-m_ref)./m_ref, W_ref, W_pred, ...
    100*(W_pred-W_ref)./W_ref, T_ref, T_pred, T_pred-T_ref, ...
    'VariableNames', {'point_id','T_evap_C','T_cond_C','freq_Hz','beta', ...
    'eta_v_reference','eta_v_predicted','eta_is_reference','eta_is_predicted', ...
    'm_dot_ref_kg_s','m_dot_pred_kg_s','m_dot_error_pct', ...
    'W_ref_kW','W_pred_kW','W_error_pct','T_dis_ref_C','T_dis_pred_C','T_dis_error_C'});
writetable(validationTable, fullfile(resultsDir, 'validation_results.csv'));

makeEfficiencyFigure(data, res, models, true, figDir);
makeEfficiencyFigure(data, res, models, false, figDir);
makeParityFigure(m_ref*1000, m_pred*1000, 'Reference mass flow rate [g/s]', ...
    'Predicted mass flow rate [g/s]', fullfile(figDir, 'parity_mass_flow.png'));
makeParityFigure(W_ref, W_pred, 'Reference power input [kW]', ...
    'Predicted power input [kW]', fullfile(figDir, 'parity_power.png'));
makeParityFigure(T_ref, T_pred, 'Reference discharge temperature [degC]', ...
    'Predicted discharge temperature [degC]', fullfile(figDir, 'parity_discharge_temperature.png'));
end

function [mape, rmse, maxape] = errorMetrics(ref, pred)
pct = abs(pred - ref) ./ abs(ref) * 100;
mape = mean(pct);
rmse = sqrt(mean((pred - ref).^2));
maxape = max(pct);
end

function makeEfficiencyFigure(data, res, models, isVolumetric, figDir)
fit = data.isFitting;
val = data.isValidation;
if isVolumetric
    yFit = res.eta_v(fit); yVal = res.eta_v(val);
    coeff = models.coeffV; ylabelText = 'Volumetric efficiency \eta_v [-]';
    fileName = 'eta_v_vs_beta.png'; titleText = 'Volumetric efficiency';
else
    yFit = res.eta_is(fit); yVal = res.eta_is(val);
    coeff = models.coeffIs; ylabelText = 'Isentropic efficiency \eta_{is} [-]';
    fileName = 'eta_is_vs_beta.png'; titleText = 'Isentropic efficiency';
end
fig = figure('Name', titleText, 'Color', 'w');
hold on; grid on;
scatter(res.beta(fit), yFit, 38, 'filled', 'DisplayName', 'Fitting data');
scatter(res.beta(val), yVal, 52, 'x', 'LineWidth', 1.2, 'DisplayName', 'Validation data');
b = linspace(min(res.beta), max(res.beta), 120).';
fn45 = 45 / models.fnRef_Hz;
X = [ones(size(b)), b, b.^2, fn45*ones(size(b)), b*fn45, fn45^2*ones(size(b))];
plot(b, X*coeff, 'k-', 'LineWidth', 1.8, 'DisplayName', '2-D model at 45 Hz');
xlabel('Pressure ratio \beta = P_{dis}/P_{suc} [-]');
ylabel(ylabelText);
title(titleText);
legend('Location', 'best');
saveas(fig, fullfile(figDir, fileName));
end

function makeParityFigure(ref, pred, xlabelText, ylabelText, fileName)
fig = figure('Color', 'w');
scatter(ref, pred, 42, 'filled'); grid on; hold on;
lo = min([ref; pred]); hi = max([ref; pred]);
pad = 0.05 * max(hi-lo, eps);
plot([lo-pad, hi+pad], [lo-pad, hi+pad], 'k--', 'LineWidth', 1.2);
xlim([lo-pad, hi+pad]); ylim([lo-pad, hi+pad]);
axis square;
xlabel(xlabelText); ylabel(ylabelText);
title('Independent validation parity');
saveas(fig, fileName);
end
