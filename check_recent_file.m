% Check the most recent file that might have been created with demo_2P_Tal5_DJ.m
fprintf('=== CHECKING RECENT FILE ===\n\n');

filepath = 'C:\Users\Ido\Desktop\For_Ido\CellReg-master\TalPipline\try 46\cellRegistered_20251030_171419.mat';

fprintf('File: %s\n', filepath);

if ~exist(filepath, 'file')
    fprintf('  STATUS: File does not exist\n');
    return;
end

try
    % Load the file
    data = load(filepath);

    % Check if cell_registered_struct exists
    if ~isfield(data, 'cell_registered_struct')
        fprintf('  STATUS: No cell_registered_struct field\n');
        return;
    end

    % Check if p_same_registered_pairs exists
    if ~isfield(data.cell_registered_struct, 'p_same_registered_pairs')
        fprintf('  STATUS: p_same_registered_pairs NOT FOUND\n');
        fprintf('  Available fields: %s\n', strjoin(fieldnames(data.cell_registered_struct), ', '));
        return;
    end

    p_same = data.cell_registered_struct.p_same_registered_pairs;

    % Display format information
    fprintf('\n  STATUS: p_same_registered_pairs FOUND!\n');
    fprintf('  Data type: %s\n', class(p_same));
    fprintf('  Dimensions: [%d x %d]\n', size(p_same, 1), size(p_same, 2));

    if iscell(p_same)
        fprintf('  Format: Cell array\n');

        % Check orientation - THIS IS THE KEY TEST
        if size(p_same, 1) == 1 && size(p_same, 2) > 1
            fprintf('\n  *** ORIENTATION: ROW vector [1 x %d] ***\n', size(p_same, 2));
            fprintf('  *** THIS IS WRONG! Should be COLUMN vector [%d x 1] ***\n', size(p_same, 2));
            fprintf('  *** FILE CREATED WITHOUT TRANSPOSE! ***\n\n');
        elseif size(p_same, 2) == 1 && size(p_same, 1) > 1
            fprintf('\n  *** ORIENTATION: COLUMN vector [%d x 1] ***\n', size(p_same, 1));
            fprintf('  *** THIS IS CORRECT! File has proper transpose ***\n\n');
        else
            fprintf('\n  ORIENTATION: 2D array [%d x %d]\n', size(p_same, 1), size(p_same, 2));
        end

        % Check first non-empty cell content
        non_empty_idx = find(~cellfun(@isempty, p_same), 1);
        if ~isempty(non_empty_idx)
            first_matrix = p_same{non_empty_idx};
            fprintf('  First matrix (cell #%d): [%d x %d] %s\n', ...
                non_empty_idx, size(first_matrix, 1), size(first_matrix, 2), class(first_matrix));

            % Show sample values
            if ~all(isnan(first_matrix(:)))
                fprintf('  Sample P(same) values:\n');
                display_rows = min(3, size(first_matrix, 1));
                display_cols = min(3, size(first_matrix, 2));
                for row = 1:display_rows
                    fprintf('    ');
                    for col = 1:display_cols
                        fprintf('%.4f  ', first_matrix(row, col));
                    end
                    fprintf('\n');
                end
            end
        end
    elseif isnumeric(p_same)
        fprintf('  Format: Numeric matrix\n');

        % Check orientation
        if size(p_same, 1) == 1 && size(p_same, 2) > 1
            fprintf('\n  *** ORIENTATION: ROW vector [1 x %d] ***\n', size(p_same, 2));
            fprintf('  *** THIS IS WRONG! Should be COLUMN vector ***\n\n');
        elseif size(p_same, 2) == 1 && size(p_same, 1) > 1
            fprintf('\n  *** ORIENTATION: COLUMN vector [%d x 1] ***\n', size(p_same, 1));
            fprintf('  *** THIS IS CORRECT! ***\n\n');
        else
            fprintf('\n  ORIENTATION: 2D matrix [%d x %d]\n', size(p_same, 1), size(p_same, 2));
        end

        % Show sample values
        fprintf('  Sample values (first 5): ');
        sample_vals = p_same(1, 1:min(5, size(p_same, 2)));
        fprintf('%s\n', num2str(sample_vals, '%.4f '));
    end

catch ME
    fprintf('  ERROR: %s\n', ME.message);
    fprintf('  Stack:\n');
    for i = 1:length(ME.stack)
        fprintf('    %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

fprintf('\n=== CHECK COMPLETE ===\n');
