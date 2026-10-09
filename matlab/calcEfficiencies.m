function res = calcEfficiencies(data, fluid, superheatK, Vd)
%CALCEFFICIENCIES Calculate refrigerant states and compressor efficiencies.
%
% For each operating point:
%   P_suc = saturation pressure at T_evap
%   P_dis = saturation pressure at T_cond
%   suction state = (P_suc, T_evap + suction superheat)
%   beta = P_dis/P_suc
%   eta_v = m_dot*v_suc/(Vd*f)
%   eta_is = m_dot*(h2s-h1)/W_el
%
% The actual discharge enthalpy implied by the tabulated power is
% h2 = h1 + W_el/m_dot; its temperature is evaluated at P_dis.

n = data.n;
TK = 273.15;
P_suc = zeros(n,1); P_dis = zeros(n,1); rho_suc = zeros(n,1);
v_suc = zeros(n,1); h1 = zeros(n,1); s1 = zeros(n,1); h2is = zeros(n,1);
T_suc = zeros(n,1); T_dis_calc = zeros(n,1);

for i = 1:n
    Te = data.T_evap(i);
    Tc = data.T_cond(i);
    P_suc(i) = getRefrigerantProp('P','T',Te+TK,'Q',0,fluid);
    P_dis(i) = getRefrigerantProp('P','T',Tc+TK,'Q',0,fluid);
    T_suc(i) = Te + TK + superheatK;
    rho_suc(i) = getRefrigerantProp('D','P',P_suc(i),'T',T_suc(i),fluid);
    v_suc(i) = 1 / rho_suc(i);
    h1(i) = getRefrigerantProp('H','P',P_suc(i),'T',T_suc(i),fluid);
    s1(i) = getRefrigerantProp('S','P',P_suc(i),'T',T_suc(i),fluid);
    h2is(i) = getRefrigerantProp('H','P',P_dis(i),'S',s1(i),fluid);

    h2_actual = h1(i) + data.W_el(i)*1000 / data.m_dot(i);
    T_dis_calc(i) = getRefrigerantProp('T','P',P_dis(i),'H',h2_actual,fluid) - TK;
end

res.P_suc = P_suc;
res.P_dis = P_dis;
res.beta = P_dis ./ P_suc;
res.rho_suc = rho_suc;
res.v_suc = v_suc;
res.h1 = h1;
res.s1 = s1;
res.h2is = h2is;
res.T_suc = T_suc;
res.T_dis_calc = T_dis_calc;
res.fn = data.f / 50;
res.Vd_dot = Vd .* data.f;
res.eta_v = data.m_dot .* v_suc ./ res.Vd_dot;
res.eta_is = data.m_dot .* (h2is - h1) ./ (data.W_el * 1000);

fprintf('Calculated properties and efficiencies for %d points.\n', n);
fprintf('  beta: %.2f to %.2f\n', min(res.beta), max(res.beta));
fprintf('  eta_v: %.3f to %.3f\n', min(res.eta_v), max(res.eta_v));
fprintf('  eta_is: %.3f to %.3f\n', min(res.eta_is), max(res.eta_is));
end
