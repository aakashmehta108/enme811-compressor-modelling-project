function val = getRefrigerantProp(output, name1, val1, name2, val2, fluid)
%GETREFRIGERANTPROP Refrigerant property from CoolProp through MATLAB/Python.
%
%   val = getRefrigerantProp('P','T',278.15,'Q',0,'R134a')
%
% CoolProp must be installed in the Python environment linked to MATLAB.
% See README.md for setup. Specific volume is calculated as 1/density in
% the calling functions because density is the more robust CoolProp output
% for the states used here.

try
    val = double(py.CoolProp.CoolProp.PropsSI( ...
        output, name1, val1, name2, val2, fluid));
catch ME
    error(['CoolProp call failed. Install CoolProp in the Python ' ...
        'environment used by MATLAB, as described in README.md. ' ...
        'Original error: %s'], ME.message);
end
end
