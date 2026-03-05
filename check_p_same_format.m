% Script to check p_same_registered_pairs format in saved files
fprintf('=== CHECKING P_SAME_REGISTERED_PAIRS FORMAT ===\n\n');

% List of files to check
files_to_check = {
    'C:\Users\Ido\Desktop\For_Ido\CellReg-master\cellRegistered_20250703_145232.mat'
    'C:\Users\Ido\Desktop\For_Ido\CellReg-master\cellreg_results\cellRegistered_20251005_005844.mat'
    'C:\Users\Ido\Desktop\For_Ido\CellReg-master\NoaPipeline\200104 try 5\cellRegistered_20251030_130943.mat'
};

for i = 1:length(files_to_check)
    filepath = files_to_check{i};

    fprintf('File %d: %s\n', i, filepath);

    if ~exist(filepath, 'file')
        fprintf('  STATUS: File does not exist\n\n');
        continue;
    end

    try
        % Load the file
        data = load(filepath);

        % Check if cell_registered_struct exists
        if ~isfield(data, 'cell_registered_struct')
            fprintf('  STATUS: No cell_registered_struct field\n\n');
            continue;
        end

        % Check if p_same_registered_pairs exists
        if ~isfield(data.cell_registered_struct, 'p_same_registered_pairs')
            fprintf('  STATUS: p_same_registered_pairs NOT FOUND\n');
            fprintf('  Available fields: %s\n\n', strjoin(fieldnames(data.cell_registered_struct), ', '));
            continue;
        end

        p_same = data.cell_registered_struct.p_same_registered_pairs;

        % Display format information
        fprintf('  STATUS: p_same_registered_pairs FOUND!\n');
        fprintf('  Data type: %s\n', class(p_same));
        fprintf('  Dimensions: [%d x %d]\n', size(p_same, 1), size(p_same, 2));

        if iscell(p_same)
            fprintf('  Format: Cell array\n');

            % Check orientation
            if size(p_same, 1) == 1
                fprintf('  Orientation: ROW vector [1 x n_cells]\n');
            elseif size(p_same, 2) == 1
                fprintf('  Orientation: COLUMN vector [n_cells x 1]\n');
            else
                fprintf('  Orientation: 2D array [%d x %d]\n', size(p_same, 1), size(p_same, 2));
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
            else
                fprintf('  WARNING: All cells are empty!\n');
            end
        elseif isnumeric(p_same)
            fprintf('  Format: Numeric matrix\n');

            % Check orientation
            if size(p_same, 1) == 1
                fprintf('  Orientation: ROW vector [1 x n_pairs]\n');
            elseif size(p_same, 2) == 1
                fprintf('  Orientation: COLUMN vector [n_pairs x 1]\n');
            else
                fprintf('  Orientation: 2D matrix [n_cells x n_pairs]\n');
            end

            % Show sample values
            fprintf('  Sample values: ');
            sample_vals = p_same(1, 1:min(5, size(p_same, 2)));
            fprintf('%s\n', num2str(sample_vals, '%.4f '));
        else
            fprintf('  WARNING: Unexpected data type!\n');
        end

        fprintf('\n');

    catch ME
        fprintf('  ERROR: %s\n\n', ME.message);
    end
end

fprintf('=== CHECK COMPLETE ===\n');
