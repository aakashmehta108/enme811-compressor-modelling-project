function data = loadCompressorData(filename)
%LOADCOMPRESSORDATA Load and quality-check the compressor performance table.
%
% Required columns:
%   point_id, dataset, T_evap_C, T_cond_C, freq_Hz, speed_rpm,
%   P_suc_bar, P_dis_bar, m_dot_kg_s, W_el_kW, T_dis_C, data_source
%
% The dataset column separates Fitting points from independent Validation
% points. Validation rows are not used to estimate regression coefficients.

if ~isfile(filename)
    error('Data file not found: %s', filename);
end

T = readtable(filename, 'TextType', 'string');
required = ["point_id","dataset","T_evap_C","T_cond_C","freq_Hz", ...
    "speed_rpm","P_suc_bar","P_dis_bar","m_dot_kg_s","W_el_kW","T_dis_C"];
missingCols = setdiff(required, string(T.Properties.VariableNames));
if ~isempty(missingCols)
    error('Missing required data columns: %s', strjoin(missingCols, ', '));
end
if any(ismissing(T(:, required(1:10))))
    warning('Rows with missing required values were removed.');
    T = rmmissing(T, 'DataVariables', required(1:10));
end

data.T = T;
data.point_id = T.point_id;
data.dataset = string(T.dataset);
data.T_evap = T.T_evap_C;       % evaporating temperature [degC]
data.T_cond = T.T_cond_C;       % condensing temperature [degC]
data.f = T.freq_Hz;             % electrical/mechanical frequency [Hz]
data.speed_rpm = T.speed_rpm;   % shaft speed [rpm]
data.P_suc_bar = T.P_suc_bar;   % tabulated suction pressure [bar]
data.P_dis_bar = T.P_dis_bar;   % tabulated discharge pressure [bar]
data.m_dot = T.m_dot_kg_s;      % reference mass flow rate [kg/s]
data.W_el = T.W_el_kW;          % reference electrical power [kW]
data.T_dis_ref = T.T_dis_C;     % reference discharge temperature [degC]
data.n = height(T);
data.isFitting = data.dataset == "Fitting";
data.isValidation = data.dataset == "Validation";

fprintf('Loaded %d operating points (%d fitting, %d validation).\n', ...
    data.n, sum(data.isFitting), sum(data.isValidation));
fprintf('  T_evap: %.0f to %.0f degC; T_cond: %.0f to %.0f degC\n', ...
    min(data.T_evap), max(data.T_evap), min(data.T_cond), max(data.T_cond));
fprintf('  Frequency: %.0f to %.0f Hz (%.0f to %.0f rpm)\n', ...
    min(data.f), max(data.f), min(data.speed_rpm), max(data.speed_rpm));
end
