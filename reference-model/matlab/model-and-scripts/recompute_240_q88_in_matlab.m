%% Independently recompute all 240 reference samples with Q8.8 arithmetic.
% Software-only comparison. This does NOT simulate the VHDL/RTL.
% Run this script in MATLAB. It loads ../model-and-scripts/MLP_reference.mat
% and writes a separate CSV so the originally archived CSV is not overwritten.

clear; clc;
scriptDir = fileparts(mfilename('fullpath'));
dataRoot = fileparts(scriptDir);
modelPath = fullfile(dataRoot, 'model-and-scripts', 'MLP_reference.mat');
if ~isfile(modelPath)
    error('Cannot find model file: %s', modelPath);
end
S = load(modelPath);
required = {'W1','b1','W2','b2','W1_q','b1_q','W2_q','b2_q','X_test','Y_test'};
for i = 1:numel(required)
    if ~isfield(S, required{i})
        error('Missing required variable %s in MLP_reference.mat', required{i});
    end
end

scale = int64(256);
X = double(S.X_test);
Y = double(S.Y_test(:));
numSamples = size(X,2);
if ~isequal(size(X), [4,240]) || numel(Y) ~= 240
    error('Expected X_test to be 4x240 and Y_test to contain 240 values.');
end

% MATLAB round() rounds ties away from zero, matching the original quantizer.
Xq = int64(round(X * 256));
W1 = double(S.W1); b1 = double(S.b1(:));
W2 = double(S.W2(:)); b2 = double(S.b2(1));
W1q = int64(S.W1_q); b1q = int64(S.b1_q(:));
W2q = int64(S.W2_q(:)); b2q = int64(S.b2_q(1));
Yfloat = W2 * max(0, W1 * X + b1) + b2;

Yraw = zeros(numSamples,1,'int64');
hiddenAcc = zeros(numSamples,8,'int64');
hiddenRelu = zeros(numSamples,8,'int64');
accMin = -int64(2^19); accMax = int64(2^19-1);
for s = 1:numSamples
    for n = 1:8
        acc = b1q(n);
        for k = 1:4
            product = Xq(k,s) * W1q(n,k);
            scaledProduct = idivide(product, scale, 'floor'); % arithmetic >> 8
            acc = acc + scaledProduct;
        end
        if acc < accMin || acc > accMax
            error('Signed 20-bit accumulator overflow at sample %d, neuron %d.', s, n);
        end
        hiddenAcc(s,n) = acc;
        hiddenRelu(s,n) = max(acc, int64(0));
        if hiddenRelu(s,n) > intmax('int16')
            error('Signed-16 activation overflow at sample %d, neuron %d.', s, n);
        end
    end
    outAcc = b2q;
    for n = 1:8
        product = hiddenRelu(s,n) * W2q(n);
        outAcc = outAcc + idivide(product, scale, 'floor');
    end
    Yraw(s) = outAcc;
end
Yq = double(Yraw) / 256;

T = table((1:numSamples)', X(1,:)', X(2,:)', X(3,:)', X(4,:)', Y, Yfloat(:), ...
    double(Yraw), Yq, Yq-Yfloat(:), Yfloat(:)-Y, Yq-Y, ...
    'VariableNames', {'sample_id','x1_float','x2_float','x3_float','x4_float', ...
    'target_float','matlab_floating_pred_recomputed','q8_8_raw_pred','q8_8_real_pred', ...
    'fixed_minus_float','float_minus_target','fixed_minus_target'});
outCsv = fullfile(scriptDir, 'test_240_predictions_matlab_recomputed.csv');
writetable(T, outCsv);

fprintf('Sample count: %d\n', numSamples);
fprintf('Fixed vs floating: MAE %.12f, RMSE %.12f, max |error| %.12f\n', ...
    mean(abs(Yq-Yfloat(:))), sqrt(mean((Yq-Yfloat(:)).^2)), max(abs(Yq-Yfloat(:))));
fprintf('Floating vs target: MAE %.12f, RMSE %.12f, max |error| %.12f\n', ...
    mean(abs(Yfloat(:)-Y)), sqrt(mean((Yfloat(:)-Y).^2)), max(abs(Yfloat(:)-Y)));
fprintf('Q8.8 vs target: MAE %.12f, RMSE %.12f, max |error| %.12f\n', ...
    mean(abs(Yq-Y)), sqrt(mean((Yq-Y).^2)), max(abs(Yq-Y)));
fprintf('First output integer: %d\n', Yraw(1));
fprintf('Max absolute hidden accumulator integer: %d\n', max(abs(hiddenAcc(:))));
fprintf('Max hidden ReLU integer: %d\n', max(hiddenRelu(:)));
fprintf('Separate CSV written: %s\n', outCsv);
fprintf('Scope: software computation only; no RTL/modelsim run.\n');
