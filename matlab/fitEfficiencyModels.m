function models = fitEfficiencyModels(data, res)
%FITEFFICIENCYMODELS Fit 1-D and 2-D polynomial efficiency correlations.
%
% Only rows marked "Fitting" are used. Validation rows remain independent.
%
% Two-dimensional candidate forms (fn = f/50):
%   A: eta = c0 + c1*beta + c2*beta^2
%   B: eta = c0 + c1*beta + c2*beta^2 + c3*fn + c4*fn^2
%   C: eta = c0 + c1*beta + c2*beta^2 + c3*fn + c4*beta*fn + c5*fn^2
%
% Form C is retained for prediction because it contains the interaction
% requested in the assignment and is compared below with A and B.

fit = data.isFitting;
beta = res.beta(fit);
fn = res.fn(fit);
etaV = res.eta_v(fit);
etaIs = res.eta_is(fit);

models.fnRef_Hz = 50;
models.designNames = ["1","beta","beta^2","fn","beta*fn","fn^2"];

XA = [ones(size(beta)), beta, beta.^2];
XB = [ones(size(beta)), beta, beta.^2, fn, fn.^2];
XC = [ones(size(beta)), beta, beta.^2, fn, beta.*fn, fn.^2];

[models.coeffV, models.statsV] = fitWithStats(XC, etaV);
[models.coeffIs, models.statsIs] = fitWithStats(XC, etaIs);

% Candidate-model comparison on fitting data only.
models.comparison = candidateComparison(XA, XB, XC, etaV, etaIs);

% One-dimensional fits at each fitting frequency.
freqs = unique(data.f(fit));
nF = numel(freqs);
oneD = struct();
oneD.frequencies_Hz = freqs;
oneD.coeffV = zeros(nF,3);
oneD.coeffIs = zeros(nF,3);
oneD.R2V = zeros(nF,1); oneD.RMSEV = zeros(nF,1);
oneD.R2Is = zeros(nF,1); oneD.RMSEIs = zeros(nF,1);
for k = 1:nF
    idx = fit & data.f == freqs(k);
    X1 = [ones(sum(idx),1), res.beta(idx), res.beta(idx).^2];
    [cV, sV] = fitWithStats(X1, res.eta_v(idx));
    [cI, sI] = fitWithStats(X1, res.eta_is(idx));
    oneD.coeffV(k,:) = cV.';
    oneD.coeffIs(k,:) = cI.';
    oneD.R2V(k) = sV.R2; oneD.RMSEV(k) = sV.RMSE;
    oneD.R2Is(k) = sI.R2; oneD.RMSEIs(k) = sI.RMSE;
end
models.oneD = oneD;

fprintf('\n2-D volumetric model: eta_v = c0+c1*beta+c2*beta^2+c3*fn+c4*beta*fn+c5*fn^2\n');
fprintf('  coefficients: %s\n', formatVector(models.coeffV));
fprintf('  R^2 = %.4f, adjusted R^2 = %.4f, RMSE = %.5f\n', ...
    models.statsV.R2, models.statsV.adjR2, models.statsV.RMSE);
fprintf('2-D isentropic model: eta_is = c0+c1*beta+c2*beta^2+c3*fn+c4*beta*fn+c5*fn^2\n');
fprintf('  coefficients: %s\n', formatVector(models.coeffIs));
fprintf('  R^2 = %.4f, adjusted R^2 = %.4f, RMSE = %.5f\n', ...
    models.statsIs.R2, models.statsIs.adjR2, models.statsIs.RMSE);
end

function comparison = candidateComparison(XA, XB, XC, etaV, etaIs)
names = ["A beta only"; "B beta + frequency"; "C beta + frequency + interaction"];
X = {XA, XB, XC};
comparison = table('Size',[3 5], ...
    'VariableTypes',{'string','double','double','double','double'}, ...
    'VariableNames',{'Model','eta_v_R2','eta_v_RMSE','eta_is_R2','eta_is_RMSE'});
for i = 1:3
    [~, sv] = fitWithStats(X{i}, etaV);
    [~, si] = fitWithStats(X{i}, etaIs);
    comparison.Model(i) = names(i);
    comparison.eta_v_R2(i) = sv.R2;
    comparison.eta_v_RMSE(i) = sv.RMSE;
    comparison.eta_is_R2(i) = si.R2;
    comparison.eta_is_RMSE(i) = si.RMSE;
end
end

function [coeff, stats] = fitWithStats(X, y)
coeff = X \ y;
yhat = X * coeff;
resid = y - yhat;
stats.RMSE = sqrt(mean(resid.^2));
ssRes = sum(resid.^2);
ssTot = sum((y - mean(y)).^2);
stats.R2 = 1 - ssRes/ssTot;
p = size(X,2) - 1;
stats.adjR2 = 1 - (1-stats.R2) * (numel(y)-1) / max(numel(y)-p-1, 1);
stats.yhat = yhat;
end

function txt = formatVector(v)
parts = arrayfun(@(x) sprintf('%.6f', x), v, 'UniformOutput', false);
txt = strjoin(parts, ', ');
end
