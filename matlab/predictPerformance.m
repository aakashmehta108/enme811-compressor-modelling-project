function [m_dot, W_el, T_dis_C, eta_v, eta_is, beta, rho_suc] = ...
    predictPerformance(T_evap, T_cond, f, models, fluid, superheatK, Vd)
%PREDICTPERFORMANCE Predict compressor performance at specified conditions.
%
% Inputs may be scalars or equal-length vectors:
%   T_evap, T_cond [degC], f [Hz]
% Outputs:
%   m_dot [kg/s], W_el [kW], T_dis_C [degC], efficiencies [-],
%   beta [-], rho_suc [kg/m3]
%
% The fitted efficiencies give
%   m_dot = eta_v*Vd*f/rho_suc
%   W_el = m_dot*(h2s-h1)/eta_is
%   h2 = h1 + (h2s-h1)/eta_is,  T_dis = T(P_dis,h2)

T_evap = T_evap(:); T_cond = T_cond(:); f = f(:);
if ~(numel(T_evap) == numel(T_cond) && numel(T_evap) == numel(f))
    error('T_evap, T_cond and f must have equal numbers of elements.');
end
n = numel(T_evap);
TK = 273.15;
m_dot = zeros(n,1); W_el = zeros(n,1); T_dis_C = zeros(n,1);
eta_v = zeros(n,1); eta_is = zeros(n,1); beta = zeros(n,1); rho_suc = zeros(n,1);

for i = 1:n
    P_suc = getRefrigerantProp('P','T',T_evap(i)+TK,'Q',0,fluid);
    P_dis = getRefrigerantProp('P','T',T_cond(i)+TK,'Q',0,fluid);
    T_suc = T_evap(i) + TK + superheatK;
    rho = getRefrigerantProp('D','P',P_suc,'T',T_suc,fluid);
    v_suc = 1 / rho;
    h1 = getRefrigerantProp('H','P',P_suc,'T',T_suc,fluid);
    s1 = getRefrigerantProp('S','P',P_suc,'T',T_suc,fluid);
    h2s = getRefrigerantProp('H','P',P_dis,'S',s1,fluid);

    b = P_dis / P_suc;
    fn = f(i) / models.fnRef_Hz;
    X = [1, b, b^2, fn, b*fn, fn^2];
    ev = X * models.coeffV;
    ei = X * models.coeffIs;
    if ev <= 0 || ei <= 0
        warning('Non-positive predicted efficiency at point %d; check extrapolation.', i);
    end

    m = ev * Vd * f(i) / v_suc;
    W = m * (h2s - h1) / ei / 1000;
    h2 = h1 + (h2s - h1) / ei;
    Tdis = getRefrigerantProp('T','P',P_dis,'H',h2,fluid) - TK;

    m_dot(i) = m; W_el(i) = W; T_dis_C(i) = Tdis;
    eta_v(i) = ev; eta_is(i) = ei; beta(i) = b; rho_suc(i) = rho;
end
end
