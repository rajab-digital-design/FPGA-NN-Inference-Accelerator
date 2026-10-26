%% ================================================================
%  MLP Reference Network
%  4 Inputs -> 8 Hidden Neurons -> 1 Output
%
%  Purpose:
%    1) Train a reference MLP in MATLAB
%    2) Export floating-point weights and biases
%    3) Quantize all parameters to signed Q8.8
%    4) Run fixed-point inference using FPGA-like arithmetic
%    5) Export test vector and expected hidden-layer outputs
%
%  Hardware target:
%    Input  : signed 16-bit Q8.8
%    Weight : signed 16-bit Q8.8
%    Bias   : signed 16-bit Q8.8
%    ACC    : signed 20-bit
%
% ================================================================

clear;
clc;
close all;

%% ---------------------------------------------------------------
% 1. Reproducibility
% ---------------------------------------------------------------

rng(42);


%% ---------------------------------------------------------------
% 2. Network dimensions
% ---------------------------------------------------------------

NUM_INPUTS  = 4;
NUM_HIDDEN  = 8;
NUM_OUTPUTS = 1;


%% ---------------------------------------------------------------
% 3. Generate a nonlinear reference dataset
%
% Inputs are in [-1, +1].
%
% The target is intentionally nonlinear so that a hidden layer
% is actually required.
% ---------------------------------------------------------------

NUM_SAMPLES = 1600;

X = 2*rand(NUM_INPUTS, NUM_SAMPLES) - 1;

x1 = X(1,:);
x2 = X(2,:);
x3 = X(3,:);
x4 = X(4,:);

Y = ...
      0.45*sin(pi*x1/2) ...
    + 0.30*(x2.^2) ...
    - 0.25*(x3.*x4) ...
    + 0.10*(x1.*x3);

Y = reshape(Y, 1, []);


%% ---------------------------------------------------------------
% 4. Shuffle and split dataset
%
%   70% training
%   15% validation
%   15% test
% ---------------------------------------------------------------

idx = randperm(NUM_SAMPLES);

n_train = floor(0.70 * NUM_SAMPLES);
n_val   = floor(0.15 * NUM_SAMPLES);

train_idx = idx(1:n_train);
val_idx   = idx(n_train+1 : n_train+n_val);
test_idx  = idx(n_train+n_val+1 : end);

X_train = X(:, train_idx);
Y_train = Y(:, train_idx);

X_val = X(:, val_idx);
Y_val = Y(:, val_idx);

X_test = X(:, test_idx);
Y_test = Y(:, test_idx);


%% ---------------------------------------------------------------
% 5. Initialize network
%
% Hidden activation:
%   ReLU
%
% Output activation:
%   Linear
% ---------------------------------------------------------------

W1 = randn(NUM_HIDDEN, NUM_INPUTS) * sqrt(2/NUM_INPUTS);
b1 = zeros(NUM_HIDDEN, 1);

W2 = randn(NUM_OUTPUTS, NUM_HIDDEN) * sqrt(2/NUM_HIDDEN);
b2 = zeros(NUM_OUTPUTS, 1);


%% ---------------------------------------------------------------
% 6. Training parameters
% ---------------------------------------------------------------

LEARNING_RATE = 0.01;
NUM_EPOCHS    = 4000;

best_val_loss = inf;

best_W1 = W1;
best_b1 = b1;
best_W2 = W2;
best_b2 = b2;


%% ---------------------------------------------------------------
% 7. Training loop
% ---------------------------------------------------------------

fprintf('\n=============================================\n');
fprintf('       MATLAB MLP TRAINING STARTED\n');
fprintf('=============================================\n');

for epoch = 1:NUM_EPOCHS

    % -------------------------------------------------------------
    % Forward pass
    % -------------------------------------------------------------

    Z1 = W1 * X_train + b1;

    A1 = Z1;
    A1(A1 < 0) = 0;        % ReLU

    Y_hat = W2 * A1 + b2;  % Linear output


    % -------------------------------------------------------------
    % Error
    % -------------------------------------------------------------

    E = Y_hat - Y_train;

    loss = mean(E(:).^2);


    % -------------------------------------------------------------
    % Backpropagation
    % -------------------------------------------------------------

    N = size(X_train, 2);

    dY = (2/N) * E;

    dW2 = dY * A1';
    db2 = sum(dY, 2);

    dA1 = W2' * dY;

    dZ1 = dA1;
    dZ1(Z1 <= 0) = 0;

    dW1 = dZ1 * X_train';
    db1 = sum(dZ1, 2);


    % -------------------------------------------------------------
    % Parameter update
    % -------------------------------------------------------------

    W1 = W1 - LEARNING_RATE * dW1;
    b1 = b1 - LEARNING_RATE * db1;

    W2 = W2 - LEARNING_RATE * dW2;
    b2 = b2 - LEARNING_RATE * db2;


    % -------------------------------------------------------------
    % Validation loss
    % -------------------------------------------------------------

    Z1_val = W1 * X_val + b1;

    A1_val = Z1_val;
    A1_val(A1_val < 0) = 0;

    Y_val_hat = W2 * A1_val + b2;

    val_error = Y_val_hat - Y_val;

    val_loss = mean(val_error(:).^2);


    % -------------------------------------------------------------
    % Keep best network
    % -------------------------------------------------------------

    if val_loss < best_val_loss

        best_val_loss = val_loss;

        best_W1 = W1;
        best_b1 = b1;
        best_W2 = W2;
        best_b2 = b2;

    end


    % -------------------------------------------------------------
    % Progress
    % -------------------------------------------------------------

    if mod(epoch, 250) == 0

        fprintf( ...
            'Epoch = %4d | Train MSE = %.8f | Val MSE = %.8f\n', ...
            epoch, loss, val_loss);

    end

end


%% ---------------------------------------------------------------
% 8. Restore best network
% ---------------------------------------------------------------

W1 = best_W1;
b1 = best_b1;
W2 = best_W2;
b2 = best_b2;


%% ---------------------------------------------------------------
% 9. Floating-point test inference
% ---------------------------------------------------------------

Z1_test = W1 * X_test + b1;

A1_test = Z1_test;
A1_test(A1_test < 0) = 0;

Y_test_hat = W2 * A1_test + b2;

test_error = Y_test_hat - Y_test;

test_mse = mean(test_error(:).^2);

test_rmse = sqrt(test_mse);


fprintf('\n=============================================\n');
fprintf('       FLOATING-POINT TEST RESULT\n');
fprintf('=============================================\n');

fprintf('Test MSE  = %.10f\n', test_mse);
fprintf('Test RMSE = %.10f\n', test_rmse);


%% ---------------------------------------------------------------
% 10. Select one deterministic test vector
% ---------------------------------------------------------------

TEST_VECTOR_INDEX = 1;

x_ref = X_test(:, TEST_VECTOR_INDEX);
y_ref = Y_test(:, TEST_VECTOR_INDEX);

z1_ref = W1 * x_ref + b1;

a1_ref = z1_ref;
a1_ref(a1_ref < 0) = 0;

y_hat_ref = W2 * a1_ref + b2;


fprintf('\n=============================================\n');
fprintf('       REFERENCE TEST VECTOR\n');
fprintf('=============================================\n');

fprintf('Input vector:\n');

for i = 1:NUM_INPUTS
    fprintf('x%d = %+0.8f\n', i, x_ref(i));
end

fprintf('\n');

fprintf('Target output     = %+0.8f\n', y_ref);
fprintf('MATLAB output     = %+0.8f\n', y_hat_ref);

fprintf('\nHidden layer pre-activation:\n');

for i = 1:NUM_HIDDEN
    fprintf('N%d = %+0.8f\n', i, z1_ref(i));
end

fprintf('\nHidden layer ReLU output:\n');

for i = 1:NUM_HIDDEN
    fprintf('N%d = %+0.8f\n', i, a1_ref(i));
end


%% ---------------------------------------------------------------
% 11. Q8.8 quantization
%
% Q8.8:
%
%     integer_value = round(real_value * 256)
%
% ---------------------------------------------------------------

SCALE = 256;

W1_q = quantize_q8_8(W1);
b1_q = quantize_q8_8(b1);

W2_q = quantize_q8_8(W2);
b2_q = quantize_q8_8(b2);

x_ref_q = quantize_q8_8(x_ref);


%% ---------------------------------------------------------------
% 12. Fixed-point inference of hidden layer
%
% This intentionally imitates the FPGA:
%
%   product = X * W
%   scaled  = arithmetic_right_shift(product, 8)
%   ACC     = bias + sum(scaled_products)
%
% All accumulation is performed in a wider integer container
% and then checked against signed 20-bit range.
% ---------------------------------------------------------------

ACC_MIN = -2^19;
ACC_MAX =  2^19 - 1;

hidden_acc_q = zeros(NUM_HIDDEN, 1, 'int64');

for n = 1:NUM_HIDDEN

    acc = int64(b1_q(n));

    for k = 1:NUM_INPUTS

        product = int64(x_ref_q(k)) * int64(W1_q(n,k));

        % FPGA equivalent:
        % arithmetic right shift by 8
        scaled_product = bitshift(product, -8);

        acc = acc + scaled_product;

    end

    hidden_acc_q(n) = acc;

end


%% ---------------------------------------------------------------
% 13. Check 20-bit accumulator range
% ---------------------------------------------------------------

for n = 1:NUM_HIDDEN

    if hidden_acc_q(n) < ACC_MIN

        error( ...
            'Neuron %d accumulator underflowed signed 20-bit range.', ...
            n);

    end

    if hidden_acc_q(n) > ACC_MAX

        error( ...
            'Neuron %d accumulator overflowed signed 20-bit range.', ...
            n);

    end

end


%% ---------------------------------------------------------------
% 14. Convert fixed-point hidden values back to real values
% ---------------------------------------------------------------

hidden_acc_real = double(hidden_acc_q) / SCALE;

hidden_relu_q = hidden_acc_q;

hidden_relu_q(hidden_relu_q < 0) = 0;

hidden_relu_real = double(hidden_relu_q) / SCALE;


%% ---------------------------------------------------------------
% 15. Fixed-point second layer
%
% Hidden output is converted back to Q8.8 before the next MAC layer.
% This matches a future hardware implementation where layer-to-layer
% data is transferred as signed 16-bit Q8.8.
% ---------------------------------------------------------------

hidden_relu_q16 = int16(hidden_relu_q);

output_acc_q = int64(b2_q);

for n = 1:NUM_HIDDEN

    product = ...
        int64(hidden_relu_q16(n)) * ...
        int64(W2_q(1,n));

    scaled_product = bitshift(product, -8);

    output_acc_q = output_acc_q + scaled_product;

end


%% ---------------------------------------------------------------
% 16. Fixed-point output
% ---------------------------------------------------------------

output_fixed_real = double(output_acc_q) / SCALE;


fprintf('\n=============================================\n');
fprintf('       Q8.8 FIXED-POINT RESULT\n');
fprintf('=============================================\n');

fprintf('\nQuantized input:\n');

for i = 1:NUM_INPUTS
    fprintf( ...
        'x%d = %6d  ->  %+0.8f\n', ...
        i, ...
        x_ref_q(i), ...
        double(x_ref_q(i))/SCALE);
end


fprintf('\nHidden-layer FPGA-like accumulators:\n');

for n = 1:NUM_HIDDEN
    fprintf( ...
        'N%d = %8d  ->  %+0.8f\n', ...
        n, ...
        hidden_acc_q(n), ...
        hidden_acc_real(n));
end


fprintf('\nHidden-layer ReLU outputs:\n');

for n = 1:NUM_HIDDEN
    fprintf( ...
        'N%d = %8d  ->  %+0.8f\n', ...
        n, ...
        hidden_relu_q(n), ...
        hidden_relu_real(n));
end


fprintf('\nFinal output:\n');

fprintf( ...
    'Q8.8 output = %8d  ->  %+0.8f\n', ...
    output_acc_q, ...
    output_fixed_real);


fprintf('\nFixed vs floating output error:\n');

fprintf( ...
    'Error = %+0.8f\n', ...
    output_fixed_real - y_hat_ref);


%% ---------------------------------------------------------------
% 17. Save MATLAB network
% ---------------------------------------------------------------

save( ...
    'MLP_reference.mat', ...
    'W1', 'b1', 'W2', 'b2', ...
    'X_test', 'Y_test', ...
    'x_ref', 'y_ref', ...
    'z1_ref', 'a1_ref', 'y_hat_ref', ...
    'W1_q', 'b1_q', ...
    'W2_q', 'b2_q', ...
    'x_ref_q', ...
    'hidden_acc_q', ...
    'hidden_relu_q', ...
    'output_acc_q');


%% ---------------------------------------------------------------
% 18. Export floating-point parameters
% ---------------------------------------------------------------

writematrix(W1, 'W1_float.txt', 'Delimiter', 'tab');
writematrix(b1, 'b1_float.txt', 'Delimiter', 'tab');

writematrix(W2, 'W2_float.txt', 'Delimiter', 'tab');
writematrix(b2, 'b2_float.txt', 'Delimiter', 'tab');

writematrix(x_ref, 'test_input_float.txt', 'Delimiter', 'tab');

writematrix(y_ref, 'test_target_float.txt', 'Delimiter', 'tab');


%% ---------------------------------------------------------------
% 19. Export Q8.8 integer values
% ---------------------------------------------------------------

writematrix(double(W1_q), 'W1_Q8_8_int.txt', 'Delimiter', 'tab');
writematrix(double(b1_q), 'b1_Q8_8_int.txt', 'Delimiter', 'tab');

writematrix(double(W2_q), 'W2_Q8_8_int.txt', 'Delimiter', 'tab');
writematrix(double(b2_q), 'b2_Q8_8_int.txt', 'Delimiter', 'tab');

writematrix(double(x_ref_q), 'test_input_Q8_8_int.txt', 'Delimiter', 'tab');

writematrix( ...
    double(hidden_acc_q), ...
    'expected_hidden_acc_Q8_8_int.txt', ...
    'Delimiter', ...
    'tab');

writematrix( ...
    double(hidden_relu_q), ...
    'expected_hidden_relu_Q8_8_int.txt', ...
    'Delimiter', ...
    'tab');


%% ---------------------------------------------------------------
% 20. Export hexadecimal values
%
% Useful for direct inspection against ModelSim.
% ---------------------------------------------------------------

write_matrix_hex16(W1_q, 'W1_Q8_8_hex.txt');
write_vector_hex16(b1_q, 'b1_Q8_8_hex.txt');
write_matrix_hex16(W2_q, 'W2_Q8_8_hex.txt');
write_vector_hex16(b2_q, 'b2_Q8_8_hex.txt');
write_vector_hex16(x_ref_q, 'test_input_Q8_8_hex.txt');
write_vector_hex20(hidden_acc_q, 'expected_hidden_acc_Q8_8_hex.txt');


%% ---------------------------------------------------------------
% 21. Summary
% ---------------------------------------------------------------

fprintf('\n=============================================\n');
fprintf('          EXPORT COMPLETED\n');
fprintf('=============================================\n');

fprintf('Network: %d -> %d -> %d\n', ...
    NUM_INPUTS, NUM_HIDDEN, NUM_OUTPUTS);

fprintf('\nGenerated files:\n');

fprintf('  MLP_reference.mat\n');

fprintf('  W1_float.txt\n');
fprintf('  b1_float.txt\n');
fprintf('  W2_float.txt\n');
fprintf('  b2_float.txt\n');
fprintf('  test_input_float.txt\n');

fprintf('  W1_Q8_8_int.txt\n');
fprintf('  b1_Q8_8_int.txt\n');
fprintf('  W2_Q8_8_int.txt\n');
fprintf('  b2_Q8_8_int.txt\n');
fprintf('  test_input_Q8_8_int.txt\n');

fprintf('  expected_hidden_acc_Q8_8_int.txt\n');
fprintf('  expected_hidden_relu_Q8_8_int.txt\n');

fprintf('  W1_Q8_8_hex.txt\n');
fprintf('  b1_Q8_8_hex.txt\n');
fprintf('  W2_Q8_8_hex.txt\n');
fprintf('  b2_Q8_8_hex.txt\n');
fprintf('  test_input_Q8_8_hex.txt\n');
fprintf('  expected_hidden_acc_Q8_8_hex.txt\n');

fprintf('\n=============================================\n');


%% ================================================================
% Local functions
% ================================================================

function q = quantize_q8_8(x)

    SCALE = 256;

    q_int = round(x * SCALE);

    q_int(q_int > 32767)  = 32767;
    q_int(q_int < -32768) = -32768;

    q = int16(q_int);

end


function write_matrix_hex16(M, filename)

    fid = fopen(filename, 'w');

    if fid == -1
        error('Cannot open file: %s', filename);
    end

    [rows, cols] = size(M);

    for r = 1:rows

        for c = 1:cols

            value = int16(M(r,c));

            u = typecast(value, 'uint16');

            fprintf(fid, '%04X', u);

            if c < cols
                fprintf(fid, '\t');
            end

        end

        fprintf(fid, '\n');

    end

    fclose(fid);

end


function write_vector_hex16(V, filename)

    fid = fopen(filename, 'w');

    if fid == -1
        error('Cannot open file: %s', filename);
    end

    V = V(:);

    for i = 1:length(V)

        value = int16(V(i));

        u = typecast(value, 'uint16');

        fprintf(fid, '%04X\n', u);

    end

    fclose(fid);

end


function write_vector_hex20(V, filename)

    fid = fopen(filename, 'w');

    if fid == -1
        error('Cannot open file: %s', filename);
    end

    V = V(:);

    for i = 1:length(V)

        value = int64(V(i));

        % Keep only the lower 20 bits.
        u = bitand(value, int64(2^20 - 1));

        fprintf(fid, '%05X\n', u);

    end

    fclose(fid);

end