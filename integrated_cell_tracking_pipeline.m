function integrated_cell_tracking_pipeline()
% INTEGRATED_CELL_TRACKING_PIPELINE - Complete pipeline from data fetch to CellReg
%
% This function integrates data fetching from DataJoint and CellReg processing
% into a single automated pipeline. All parameters are collected at the start.
% MODIFIED: Now tracks ALL cells including those filtered out by probability threshold

    %% Step 1: Collect all parameters at the start
    fprintf('\n=== INTEGRATED CELL TRACKING & REGISTRATION PIPELINE ===\n\n');
    
    % Get subject and session information
    params = collect_pipeline_parameters();
    
    if isempty(params)
        fprintf('Pipeline cancelled by user.\n');
        return;
    end
    
    % Start diary to capture console output
    diary_file = fullfile(params.results_directory, sprintf('pipeline_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    diary(diary_file);
    diary on;
    
    fprintf('Log file created: %s\n\n', diary_file);
    
    %% Step 2: Fetch data and create cell tensors with visualizations
    % MODIFIED: Now also returns roi_mappings
    fprintf('\n--- STAGE 1: DATA FETCHING AND PREPROCESSING ---\n');
    
    [file_names, results_structures, roi_mappings] = generate_cell_tensors_and_visualize(params.subject_id, ...
                                                                           params.sessions, ...
                                                                           params.temp_data_path, ...
                                                                           params.results_directory, ...
                                                                           params.figures_visibility, ...
                                                                           params.cell_prob_threshold);
    
    if isempty(file_names)
        error('Failed to generate cell tensor files');
    end
    
    % MODIFIED: Store roi_mappings and session_numbers in params for later use
    params.roi_mappings = roi_mappings;
    params.session_numbers = params.sessions;
    
    fprintf('\n--- Initial analysis complete. Starting CellReg processing... ---\n');
    pause(2); % Brief pause before CellReg starts
    
    %% Step 3: Run CellReg with generated files
    fprintf('\n--- STAGE 2: CELL REGISTRATION ---\n');
    
    run_cellreg_pipeline(file_names, params);
    
    fprintf('\n=== PIPELINE COMPLETED SUCCESSFULLY ===\n');
    fprintf('Summary log saved to: %s\n', diary_file);

    % Turn off diary
    diary off;

    % Show success notification popup
    msgbox(sprintf('Pipeline completed successfully!\n\nResults saved to:\n%s\n\nLog file:\n%s', ...
                   params.results_directory, diary_file), ...
           'Pipeline Complete', 'help', 'modal');

end

%% ========================================================================
%% PARAMETER COLLECTION
%% ========================================================================

function params = collect_pipeline_parameters()
% COLLECT_PIPELINE_PARAMETERS - Collect all parameters needed for the pipeline

    % Dialog 1: Subject and Sessions
    prompt1 = {
        'Subject ID:'
        'Sessions (comma-separated, e.g., 1,2,3,6,7,8):'
        'Temporary data path (for .mat files):'
        'Cell probability threshold (0-1, only cells above this will be included):'
    };
    dlgtitle1 = 'Data Extraction Parameters';
    dims1 = [1 60];
    definput1 = {'101106', '3,4,7', './temp_data/', '0.5'};
    answer1 = inputdlg(prompt1, dlgtitle1, dims1, definput1);
    
    if isempty(answer1)
        params = [];
        return;
    end
    
    params.subject_id = str2double(answer1{1});
    sessions_str = strrep(answer1{2}, ' ', '');
    params.sessions = str2num(['[' sessions_str ']']);
    params.temp_data_path = answer1{3};
    params.cell_prob_threshold = str2double(answer1{4});
    
    % Dialog 2: CellReg Basic Parameters
    prompt2 = {
        'Microns per pixel:'
        'Memory efficient run:'
        'Use parallel processing:'
        'Show figures during processing:'
        'Number of zoomed cell figures to generate:'
    };
    dlgtitle2 = 'CellReg Basic Parameters';
    dims2 = [1 60];
    definput2 = {'1.367', '0 (No)', 'true (Yes)', 'off (No)', '50'};
    answer2 = inputdlg(prompt2, dlgtitle2, dims2, definput2);

    if isempty(answer2)
        params = [];
        return;
    end

    params.microns_per_pixel = str2double(answer2{1});
    % Parse memory efficient: accept 0, 1, 'no', 'yes'
    mem_str = lower(strtrim(answer2{2}));
    if contains(mem_str, 'yes') || contains(mem_str, '1')
        params.memory_efficient_run = 1;
    else
        params.memory_efficient_run = 0;
    end
    % Parse parallel processing
    par_str = lower(strtrim(answer2{3}));
    if contains(par_str, 'yes') || contains(par_str, 'true')
        params.use_parallel_processing = true;
    else
        params.use_parallel_processing = false;
    end
    % Parse figures visibility
    fig_str = lower(strtrim(answer2{4}));
    if contains(fig_str, 'yes') || contains(fig_str, 'on')
        params.figures_visibility = 'on';
    else
        params.figures_visibility = 'off';
    end
    params.n_zoomed = str2double(answer2{5});

    % Select results directory using GUI
    results_directory = uigetdir(pwd, 'Select directory to save results');
    if isequal(results_directory, 0)
        results_directory = fullfile(pwd, 'cellreg_results');
        fprintf('No directory selected. Using default: %s\n', results_directory);
    end
    params.results_directory = results_directory;

    % Dialog 3: CellReg Alignment Parameters - Use dropdown for alignment type
    alignment_types = {'Translations', 'Translations and Rotations', 'Non-rigid'};
    [alignment_idx, tf] = listdlg('PromptString', 'Select alignment type:', ...
                                  'SelectionMode', 'single', ...
                                  'ListString', alignment_types, ...
                                  'InitialValue', 2, ...
                                  'Name', 'Alignment Type');
    if ~tf
        params = [];
        return;
    end
    params.alignment_type = alignment_types{alignment_idx};

    prompt3 = {
        'Maximal rotation (degrees):'
        'Transformation smoothness (0.5-3):'
        'Reference session index (1 to N):'
    };
    dlgtitle3 = 'CellReg Alignment Parameters';
    dims3 = [1 60];
    definput3 = {'30', '2', '1'};
    answer3 = inputdlg(prompt3, dlgtitle3, dims3, definput3);

    if isempty(answer3)
        params = [];
        return;
    end

    params.maximal_rotation = str2double(answer3{1});
    params.transformation_smoothness = str2double(answer3{2});
    params.reference_session_index = str2double(answer3{3});

    % Dialog 4: CellReg Registration Parameters - Use dropdowns for choices
    registration_approaches = {'Probabilistic', 'Simple threshold'};
    [reg_idx, tf] = listdlg('PromptString', 'Select registration approach:', ...
                            'SelectionMode', 'single', ...
                            'ListString', registration_approaches, ...
                            'InitialValue', 1, ...
                            'Name', 'Registration Approach');
    if ~tf
        params = [];
        return;
    end
    params.registration_approach = registration_approaches{reg_idx};

    model_types = {'Spatial correlation', 'Centroid distance', 'best_model_string'};
    [model_idx, tf] = listdlg('PromptString', 'Select model type:', ...
                              'SelectionMode', 'single', ...
                              'ListString', model_types, ...
                              'InitialValue', 3, ...
                              'Name', 'Model Type');
    if ~tf
        params = [];
        return;
    end
    params.model_type = model_types{model_idx};

    prompt4 = {
        'Sufficient correlation centroids:'
        'Sufficient correlation footprints:'
        'Maximal distance (micrometers):'
        'P_same certainty threshold:'
        'P_same threshold:'
    };
    dlgtitle4 = 'CellReg Registration Parameters';
    dims4 = [1 60];
    definput4 = {'0.2', '0.3', '10', '0.95', '0.5'};
    answer4 = inputdlg(prompt4, dlgtitle4, dims4, definput4);

    if isempty(answer4)
        params = [];
        return;
    end

    params.sufficient_correlation_centroids = str2double(answer4{1});
    params.sufficient_correlation_footprints = str2double(answer4{2});
    params.maximal_distance = str2double(answer4{3});
    params.p_same_certainty_threshold = str2double(answer4{4});
    params.p_same_threshold = str2double(answer4{5});
    params.initial_registration_type = 'best_model_string';
    
    % Create necessary directories
    if ~exist(params.temp_data_path, 'dir')
        mkdir(params.temp_data_path);
    end
    if ~exist(params.results_directory, 'dir')
        mkdir(params.results_directory);
        fprintf('Created results directory: %s\n', params.results_directory);
    end
    
    % Display summary
    fprintf('\n=== PIPELINE CONFIGURATION ===\n');
    fprintf('Subject ID: %d\n', params.subject_id);
    fprintf('Sessions: [%s]\n', num2str(params.sessions));
    fprintf('Cell probability threshold: %.2f\n', params.cell_prob_threshold);
    fprintf('Temporary data path: %s\n', params.temp_data_path);
    fprintf('Results will be saved to: %s\n', params.results_directory);
    fprintf('Microns per pixel: %.2f\n', params.microns_per_pixel);
    fprintf('============================\n\n');
    
end

%% ========================================================================
%% DATA GENERATION WITH VISUALIZATION
%% ========================================================================

function [file_names, results_structures, roi_mappings] = generate_cell_tensors_and_visualize(subject_id, sessions, save_path, results_path, figures_visibility, cell_prob_threshold)
% GENERATE_CELL_TENSORS_AND_VISUALIZE - Create .mat files and generate all initial visualizations
% MODIFIED: Now also returns roi_mappings structure

    n_sessions = length(sessions);
    file_names = cell(1, n_sessions);
    
    % MODIFIED: Initialize roi_mappings structure
    roi_mappings = struct('session', {}, 'original_roi_numbers', {}, 'filtered_indices', {}, ...
                         'n_total', {}, 'n_kept', {});
    
    results_structures = struct('subject_id', {}, 'session', {}, 'cell_tensor', {}, ...
                               'fig_handles', {}, 'mean_img_enhanced', {}, 'rois', {}, 'success', {});
    
    % Create figures directory for initial analysis
    initial_figs_dir = fullfile(results_path, 'Initial_Analysis_Figures');
    if ~exist(initial_figs_dir, 'dir')
        mkdir(initial_figs_dir);
    end
    
    fprintf('Initial analysis figures will be saved to: %s\n', initial_figs_dir);
    fprintf('Cell probability threshold: %.2f (only cells above this threshold will be included)\n\n', cell_prob_threshold);
    
    % Set options for visualization
    options.show_figures = strcmp(figures_visibility, 'on');
    options.save_figures = true;
    options.save_path = initial_figs_dir;
    
    % Process each session
    for i = 1:n_sessions
        sess = sessions(i);
        fprintf('Processing Subject %d, Session %d (%d/%d)...\n', ...
                subject_id, sess, i, n_sessions);
        
        try
            % MODIFIED: Fetch session data with probability filtering AND mapping
            [mean_img, mean_img_enhanced, rois, rois_all, cell_tensor, n_filtered, roi_mapping] = ...
                fetch_session_data_with_mapping(subject_id, sess, cell_prob_threshold);
            
            fprintf('  Total ROIs detected: %d\n', n_filtered.total);
            fprintf('  ROIs above threshold (%.2f): %d\n', cell_prob_threshold, n_filtered.kept);
            fprintf('  ROIs filtered out: %d\n', n_filtered.filtered);
            
            % MODIFIED: Store the mapping
            roi_mappings(i).session = sess;
            roi_mappings(i).original_roi_numbers = roi_mapping.original_roi_numbers;
            roi_mappings(i).filtered_indices = roi_mapping.filtered_indices;
            roi_mappings(i).probabilities = roi_mapping.probabilities;
            roi_mappings(i).n_total = n_filtered.total;
            roi_mappings(i).n_kept = n_filtered.kept;
            
            % Generate visualizations for this session
            fprintf('  Generating visualizations...\n');
            
            fig_handles = struct();
            
            fprintf('    Creating field of view...\n');
            fig_handles.fov = visualize_field_of_view(mean_img, mean_img_enhanced, subject_id, sess, options);
            
            fprintf('    Creating ROI visualization...\n');
            fig_handles.roi = visualize_rois(mean_img_enhanced, rois, subject_id, sess, options);
            
            fprintf('    Creating ROI probability...\n');
            fig_handles.roi_probability = visualize_rois_probability(mean_img_enhanced, rois_all, subject_id, sess, options);
            
            fprintf('    Creating cutoff...\n');
            fig_handles.cutoff = visualize_cutoff_image(cell_tensor, subject_id, sess, options, n_filtered.kept);
            
            fprintf('    Creating simple ROIs...\n');
            fig_handles.simple = visualize_simple_rois(mean_img_enhanced, rois, subject_id, sess, options);
            
            % Store results for comparison plots
            results_structures(i).subject_id = subject_id;
            results_structures(i).session = sess;
            results_structures(i).cell_tensor = cell_tensor;
            results_structures(i).fig_handles = fig_handles;
            results_structures(i).mean_img = mean_img;
            results_structures(i).mean_img_enhanced = mean_img_enhanced;
            results_structures(i).rois = rois;
            results_structures(i).success = true;
            
            % Create spatial footprints from cell tensor
            footprint = create_footprints_from_tensor(cell_tensor);
            
            % Save to .mat file
            filename = sprintf('Subject_%d_Session_%d_footprints.mat', ...
                              subject_id, sess);
            filepath = fullfile(save_path, filename);
            % IMPORTANT: Save mean_img_enhanced along with footprint 
            save(filepath, 'footprint', 'mean_img', '-v7.3');
            
            file_names{i} = filepath;
            fprintf('  Saved: %s\n\n', filename);
            
        catch ME
            fprintf('  ERROR: Failed to process session %d: %s\n\n', sess, ME.message);
            file_names = [];
            roi_mappings = [];
            return;
        end
    end
    
    % Generate comparison figures across sessions
    fprintf('\n--- Generating cross-session comparison figures ---\n');
    successful = [results_structures.success];
    if sum(successful) > 1
        results_success = results_structures(successful);
        
        fprintf('Creating session contour comparison...\n');
        compare_sessions_contours(results_success, subject_id, options);

        fprintf('Creating session cutoff comparison...\n');
        compare_sessions_cutoff(results_success, subject_id, options);

        fprintf('Creating baseline mean image comparison...\n');
        compare_sessions_baseline(results_success, subject_id, options);

        fprintf('Creating enhanced image comparison...\n');
        compare_sessions_enhanced(results_success, subject_id, options);
    end
    
    fprintf('\nInitial analysis and visualization complete!\n');
    fprintf('All figures saved to: %s\n', initial_figs_dir);
    
end

%% ========================================================================
%% DATA FETCHING WITH MAPPING - MODIFIED SECTION
%% ========================================================================

function [mean_img, mean_img_enhanced, rois, rois_all, cell_tensor, n_filtered, roi_mapping] = fetch_session_data_with_mapping(subject_id, session, cell_prob_threshold)
% FETCH_SESSION_DATA_WITH_MAPPING - Fetch all data for a given subject and session with probability filtering
% MODIFIED: Now also returns roi_mapping structure that tracks original ROI indices

    fprintf('  Fetching mean_img...\n');
    mean_img_struct = fetch(IMGt.Plane & ...
                      sprintf('subject_id=%d AND session=%d', subject_id, session), ...
                      'mean_img');
    
    fprintf('  Fetching mean_img_enhanced...\n');
    mean_img_enhanced_struct = fetch(IMGt.Plane & ...
                      sprintf('subject_id=%d AND session=%d', subject_id, session), ...
                      'mean_img_enhanced');
    
    % Extract image arrays from structs
    if isstruct(mean_img_struct) && isfield(mean_img_struct, 'mean_img')
        mean_img = mean_img_struct.mean_img;
    else
        mean_img = mean_img_struct;
    end
    
    if isstruct(mean_img_enhanced_struct) && isfield(mean_img_enhanced_struct, 'mean_img_enhanced')
        mean_img_enhanced = mean_img_enhanced_struct.mean_img_enhanced;
    else
        mean_img_enhanced = mean_img_enhanced_struct;
    end
    
    % Convert to double if needed
    if ~isa(mean_img, 'double')
        mean_img = double(mean_img); 
    end
    if ~isa(mean_img_enhanced, 'double')
        mean_img_enhanced = double(mean_img_enhanced);
    end
    
    % Fetch cell probabilities
    IsCellProb_raw = fetch(IMGt.IsCellProb & ...
                           sprintf('subject_id=%d AND session=%d', subject_id, session), ...
                           'probability');
    IsCellProb = [IsCellProb_raw.probability];
    
    % Fetch ROI data
    rois_raw = fetch(IMGt.ROI & ...
                     sprintf('subject_id=%d AND session=%d', subject_id, session), ...
                     'roi_x_pix', 'roi_y_pix', 'roi_number_uid', 'roi_centroid_x', 'roi_centroid_y');
    
    % Store ALL ROIs for probability visualization
    rois_all.roi_x_pix = {rois_raw.roi_x_pix};
    rois_all.roi_y_pix = {rois_raw.roi_y_pix};
    rois_all.roi_number_uid = [rois_raw.roi_number_uid];
    rois_all.roi_centroid_x = [rois_raw.roi_centroid_x];
    rois_all.roi_centroid_y = [rois_raw.roi_centroid_y];
    rois_all.probability = IsCellProb;
    
    % Filter ROIs based on probability threshold
    valid_indices = IsCellProb >= cell_prob_threshold;
    n_filtered.total = length(IsCellProb);
    n_filtered.kept = sum(valid_indices);
    n_filtered.filtered = n_filtered.total - n_filtered.kept;
    
    % MODIFIED: CREATE MAPPING: original ROI number -> filtered index (or 0 if filtered out)
    roi_mapping.original_roi_numbers = [rois_raw.roi_number_uid];  % Original ROI numbers (1 to N_total)
    roi_mapping.filtered_indices = zeros(1, n_filtered.total);  % Will be 1 to N_kept for kept ROIs, 0 for filtered
    roi_mapping.probabilities = IsCellProb;  % Store all probabilities

    filtered_counter = 0;
    for i = 1:n_filtered.total
        if valid_indices(i)
            filtered_counter = filtered_counter + 1;
            roi_mapping.filtered_indices(i) = filtered_counter;
        end
    end
    
    % Apply filtering to ROIs for tensor and CellReg
    rois_raw_filtered = rois_raw(valid_indices);
    IsCellProb_filtered = IsCellProb(valid_indices);
    
    % Organize filtered ROI data
    rois.roi_x_pix = {rois_raw_filtered.roi_x_pix};
    rois.roi_y_pix = {rois_raw_filtered.roi_y_pix};
    rois.roi_number_uid = [rois_raw_filtered.roi_number_uid];
    rois.roi_centroid_x = [rois_raw_filtered.roi_centroid_x];
    rois.roi_centroid_y = [rois_raw_filtered.roi_centroid_y];
    rois.probability = IsCellProb_filtered;
    
    % Build cell tensor using only filtered ROIs
    cell_tensor = build_cell_tensor_filtered(subject_id, session, rois_raw_filtered, mean_img);
    
end

function cell_tensor = build_cell_tensor_filtered(subject_id, session, rois_filtered, mean_img)
% BUILD_CELL_TENSOR_FILTERED - Create 3D tensor using pre-filtered ROIs
    
    num_cells = length(rois_filtered);
    [ny, nx] = size(mean_img);
    
    % Convert mean_img to double if necessary
    if ~isa(mean_img, 'double') && ~isa(mean_img, 'single')
        mean_img = double(mean_img);
    end
    
    % Initialize cell tensor
    cell_tensor = zeros(num_cells, ny, nx, 'like', mean_img);
    
    % Loop over filtered ROIs
    for i = 1:num_cells
        xi = rois_filtered(i).roi_x_pix;
        yi = rois_filtered(i).roi_y_pix;
        
        % Create mask for this ROI
        mask = false(ny, nx);
        
        % Ensure indices are within bounds
        valid_idx = (yi >= 1) & (yi <= ny) & (xi >= 1) & (xi <= nx);
        xi = xi(valid_idx);
        yi = yi(valid_idx);
        
        if ~isempty(xi) && ~isempty(yi)
            mask(sub2ind([ny, nx], yi, xi)) = true;
            
            % Place masked image into tensor
            temp_img = zeros(ny, nx, 'like', mean_img);
            temp_img(mask) = mean_img(mask);
            cell_tensor(i,:,:) = temp_img;
        end
    end
end

function footprint = create_footprints_from_tensor(cell_tensor)
% CREATE_FOOTPRINTS_FROM_TENSOR - Convert cell tensor to CellReg format

    n_cells = size(cell_tensor, 1);
    footprint = cell(1, n_cells);
    
    for i = 1:n_cells
        footprint{i} = squeeze(cell_tensor(i, :, :));
    end
    
end

%% ========================================================================
%% EXPANDED REGISTRATION TABLE CREATION - NEW FUNCTION
%% ========================================================================

function create_expanded_registration_table(optimal_cell_to_index_map, roi_mappings, results_directory, session_numbers)
% CREATE_EXPANDED_REGISTRATION_TABLE - Create table including ALL cells (even filtered ones)
%
% This creates a registration table where:
% - Each row is an original ROI from any session
% - Columns are sessions
% - Values are:
%   - 0 if cell doesn't exist in that session OR was filtered out
%   - Original ROI number if cell exists and was kept in registration
%
% The table will be MUCH larger than optimal_cell_to_index_map because it includes
% all cells that were filtered out due to low probability.

    fprintf('\n--- Creating Expanded Registration Table (All Cells) ---\n');
    
    n_sessions = length(session_numbers);
    
    % Find maximum number of original ROIs in any session
    max_original_rois = 0;
    for i = 1:n_sessions
        max_original_rois = max(max_original_rois, roi_mappings(i).n_total);
    end
    
    % Create mapping: (session, filtered_index) -> registered_cell_id
    % This allows us to look up which registered cell a filtered ROI belongs to
    filtered_to_registered = cell(1, n_sessions);
    for sess = 1:n_sessions
        filtered_to_registered{sess} = zeros(1, roi_mappings(sess).n_kept);
    end
    
    % Fill in the mapping from optimal_cell_to_index_map
    n_registered_cells = size(optimal_cell_to_index_map, 1);
    for cell_id = 1:n_registered_cells
        for sess = 1:n_sessions
            filtered_idx = optimal_cell_to_index_map(cell_id, sess);
            if filtered_idx > 0
                filtered_to_registered{sess}(filtered_idx) = cell_id;
            end
        end
    end
    
    % Create expanded table
    % We'll create one row per UNIQUE registered cell, plus one row for each filtered-out cell
    
    % First, add all registered cells
    expanded_table = optimal_cell_to_index_map;  % Start with registered cells
    
    % Now add filtered-out cells (one row per session's filtered cells)
    for sess = 1:n_sessions
        n_total = roi_mappings(sess).n_total;
        filtered_indices = roi_mappings(sess).filtered_indices;
        
        % Find ROIs that were filtered out (filtered_indices == 0)
        filtered_out_mask = (filtered_indices == 0);
        filtered_out_original_rois = roi_mappings(sess).original_roi_numbers(filtered_out_mask);
        
        fprintf('  Session %d: Adding %d filtered-out cells\n', session_numbers(sess), length(filtered_out_original_rois));
        
        % Add one row for each filtered-out cell
        for i = 1:length(filtered_out_original_rois)
            new_row = zeros(1, n_sessions);
            % Mark this cell as existing only in its original session
            % We'll use negative indices to distinguish filtered cells
            new_row(sess) = -filtered_out_original_rois(i);  % Negative = filtered out
            expanded_table = [expanded_table; new_row];
        end
    end
    
    % Create more useful version: map back to original ROI numbers
    expanded_table_original_rois = zeros(size(expanded_table));
    
    for cell_id = 1:size(expanded_table, 1)
        for sess = 1:n_sessions
            idx = expanded_table(cell_id, sess);
            
            if idx > 0
                % This is a kept ROI - map filtered index back to original ROI number
                % Find which original ROI corresponds to this filtered index
                original_roi_num = find(roi_mappings(sess).filtered_indices == idx, 1);
                if ~isempty(original_roi_num)
                    expanded_table_original_rois(cell_id, sess) = roi_mappings(sess).original_roi_numbers(original_roi_num);
                end
            elseif idx < 0
                % This is a filtered-out ROI - already has original ROI number (negated)
                expanded_table_original_rois(cell_id, sess) = -idx;
            end
            % idx == 0 means cell doesn't exist in this session
        end
    end
    
    % Save both versions
    cell_registered_expanded = struct();
    cell_registered_expanded.cell_to_index_map_filtered = expanded_table;  % Uses filtered indices (positive) or -original_roi (negative)
    cell_registered_expanded.cell_to_index_map_original_rois = expanded_table_original_rois;  % Uses original ROI numbers
    cell_registered_expanded.session_numbers = session_numbers;
    cell_registered_expanded.roi_mappings = roi_mappings;
    cell_registered_expanded.description = 'Expanded registration table including ALL cells (even those filtered out by probability threshold)';
    cell_registered_expanded.note = 'In cell_to_index_map_original_rois: 0 = cell not present in session, >0 = original ROI number';
    
    % Save to file
    save(fullfile(results_directory, ['cellRegistered_expanded_' datestr(clock, 'yyyymmdd_HHMMss') '.mat']), ...
         'cell_registered_expanded', '-v7.3');
    
    fprintf('  Expanded table dimensions: %d cells x %d sessions\n', size(expanded_table, 1), n_sessions);
    fprintf('  Original registered cells: %d\n', n_registered_cells);
    fprintf('  Additional filtered cells: %d\n', size(expanded_table, 1) - n_registered_cells);
    fprintf('  Saved to: cellRegistered_expanded_*.mat\n');
    
    % Create summary table (FIXED: calculate n_filtered instead of accessing it)
    fprintf('\n  Summary by session:\n');
    for sess = 1:n_sessions
        n_registered_in_sess = sum(expanded_table_original_rois(:, sess) > 0);
        n_filtered_out = roi_mappings(sess).n_total - roi_mappings(sess).n_kept;  % FIXED: Calculate instead of access
        fprintf('    Session %d: %d total ROIs, %d kept (registered), %d filtered out\n', ...
                session_numbers(sess), roi_mappings(sess).n_total, ...
                roi_mappings(sess).n_kept, n_filtered_out);
    end
end

function create_roi_to_cellreg_lookup_tables(optimal_cell_to_index_map, roi_mappings, results_directory, session_numbers, subject_id)
% CREATE_ROI_TO_CELLREG_LOOKUP_TABLES - Create structured lookup table
%
% Creates a table with 4 columns:
%   1. CellReg_ID: The CellReg cell index (0 if filtered out)
%   2. ROI_number: Original ROI number from database
%   3. Session: Session number
%   4. P_same_matrix: [n_sessions x n_sessions] matrix of P(same) values for this cell

    fprintf('\n--- Creating Structured ROI-to-CellReg Lookup Table ---\n');
    
    if nargin < 5
        subject_id = NaN;
    end
    
    % Load p_same_registered_pairs from the most recent cellRegistered file
    cellreg_files = dir(fullfile(results_directory, 'cellRegistered_*.mat'));
    if isempty(cellreg_files)
        fprintf('  WARNING: No cellRegistered file found in %s\n', results_directory);
        has_p_same = false;
        p_same_registered_pairs = [];
    else
        % Get the most recent file
        [~, newest_idx] = max([cellreg_files.datenum]);
        cellreg_file = fullfile(results_directory, cellreg_files(newest_idx).name);
        
        fprintf('  Loading p_same data from: %s\n', cellreg_files(newest_idx).name);
        cellreg_data = load(cellreg_file);
        
        if isfield(cellreg_data, 'cell_registered_struct') && ...
           isfield(cellreg_data.cell_registered_struct, 'p_same_registered_pairs')
            p_same_registered_pairs = cellreg_data.cell_registered_struct.p_same_registered_pairs;
            has_p_same = true;
            fprintf('    P_same data loaded successfully\n');
            fprintf('    Size: [%d cells x %d pairs]\n', size(p_same_registered_pairs, 1), size(p_same_registered_pairs, 2));
        else
            fprintf('    WARNING: p_same_registered_pairs not found in cellRegistered file\n');
            has_p_same = false;
            p_same_registered_pairs = [];
        end
    end
    
    n_sessions = length(session_numbers);
    
    % Calculate total number of ROIs across all sessions
    total_rois = 0;
    for sess_idx = 1:n_sessions
        total_rois = total_rois + roi_mappings(sess_idx).n_total;
    end
    
    fprintf('  Total ROIs across all sessions: %d\n', total_rois);
    
    % Initialize arrays for the 4 columns
    CellReg_ID_array = zeros(total_rois, 1);
    ROI_number_array = zeros(total_rois, 1);
    Session_array = zeros(total_rois, 1);
    P_same_matrix_cell = cell(total_rois, 1);  % Cell array to store matrices
    
    % Fill in the table
    current_row = 1;
    
    for sess_idx = 1:n_sessions
        sess_num = session_numbers(sess_idx);
        
        % Get mapping info for this session
        original_roi_numbers = roi_mappings(sess_idx).original_roi_numbers;
        filtered_indices = roi_mappings(sess_idx).filtered_indices;
        n_rois_this_session = roi_mappings(sess_idx).n_total;
        
        % Process each ROI in this session
        for roi_idx = 1:n_rois_this_session
            % Column 2: ROI number from database
            ROI_number_array(current_row) = original_roi_numbers(roi_idx);
            
            % Column 3: Session number
            Session_array(current_row) = sess_num;
            
            % Find CellReg ID
            filtered_idx = filtered_indices(roi_idx);
            
            if filtered_idx > 0
                % Find which CellReg cell this belongs to
                cellreg_id = find(optimal_cell_to_index_map(:, sess_idx) == filtered_idx, 1);
                
                if ~isempty(cellreg_id)
                    % Column 1: CellReg ID
                    CellReg_ID_array(current_row) = cellreg_id;
                    
                    % Column 4: P_same matrix for this cell
                    if has_p_same && cellreg_id <= size(p_same_registered_pairs, 1)
                        % Extract and reshape the P_same values into a matrix
                        P_same_matrix_cell{current_row} = extract_p_same_matrix_from_pairs(...
                            cellreg_id, p_same_registered_pairs, n_sessions);
                    else
                        P_same_matrix_cell{current_row} = [];
                    end
                else
                    CellReg_ID_array(current_row) = 0;
                    P_same_matrix_cell{current_row} = [];
                end
            else
                % Filtered out
                CellReg_ID_array(current_row) = 0;
                P_same_matrix_cell{current_row} = [];
            end
            
            current_row = current_row + 1;
        end
        
        % Print session summary
        session_registered = sum(CellReg_ID_array((current_row - n_rois_this_session):(current_row - 1)) > 0);
        session_filtered = n_rois_this_session - session_registered;
        fprintf('  Session %d: %d ROIs (%d registered, %d filtered out)\n', ...
                sess_num, n_rois_this_session, session_registered, session_filtered);
    end
    
    % Create the final lookup table structure
    ROI_to_CellReg_Lookup = struct();
    ROI_to_CellReg_Lookup.CellReg_ID = CellReg_ID_array;        % Column 1
    ROI_to_CellReg_Lookup.ROI_number = ROI_number_array;        % Column 2
    ROI_to_CellReg_Lookup.Session = Session_array;              % Column 3
    ROI_to_CellReg_Lookup.P_same_matrix = P_same_matrix_cell;   % Column 4 (cell array of matrices)
    
    % Metadata
    ROI_to_CellReg_Lookup.subject_id = subject_id;
    ROI_to_CellReg_Lookup.session_numbers = session_numbers;
    ROI_to_CellReg_Lookup.total_rois = total_rois;
    ROI_to_CellReg_Lookup.description = 'Structured lookup table: CellReg_ID | ROI_number | Session | P_same_matrix';
    ROI_to_CellReg_Lookup.note = 'CellReg_ID = 0 means ROI was filtered out. P_same_matrix is [n_sessions x n_sessions] for each registered cell.';
    
    % Summary statistics
    n_registered_total = sum(CellReg_ID_array > 0);
    n_filtered_total = sum(CellReg_ID_array == 0);
    
    fprintf('\n  Lookup table summary:\n');
    fprintf('    Total ROIs: %d\n', total_rois);
    fprintf('    Registered (CellReg_ID > 0): %d\n', n_registered_total);
    fprintf('    Filtered out (CellReg_ID = 0): %d\n', n_filtered_total);
    fprintf('    Structure: 4 columns [CellReg_ID, ROI_number, Session, P_same_matrix]\n');
    if has_p_same
        fprintf('    P_same matrices included: %d x %d for each registered cell\n', n_sessions, n_sessions);
    else
        fprintf('    P_same matrices: Not available\n');
    end
    
    % Save to .mat file
    mat_filename = fullfile(results_directory, ['ROI_to_CellReg_Lookup_' datestr(clock, 'yyyymmdd_HHMMss') '.mat']);
    save(mat_filename, 'ROI_to_CellReg_Lookup', '-v7.3');
    
    fprintf('  Saved lookup table to: %s\n', mat_filename);
    fprintf('  Lookup table creation complete!\n');
end

function p_same_matrix = extract_p_same_matrix_from_pairs(cell_idx, p_same_registered_pairs, n_sessions)
% EXTRACT_P_SAME_MATRIX_FROM_PAIRS - Convert p_same_registered_pairs vector to matrix
% 
% p_same_registered_pairs is [n_cells x n_pairs] where n_pairs = n_sessions*(n_sessions-1)/2
% Each row contains pairwise probabilities in order: (1,2), (1,3), ..., (1,n), (2,3), ..., (n-1,n)

    % Initialize symmetric matrix with diagonal = 1
    p_same_matrix = NaN(n_sessions, n_sessions);
    for i = 1:n_sessions
        p_same_matrix(i, i) = 1;  % Same session = P(same) = 1
    end
    
    % Fill in pairwise values
    pair_vector = p_same_registered_pairs(cell_idx, :);
    pair_idx = 0;
    
    for sess_i = 1:n_sessions-1
        for sess_j = sess_i+1:n_sessions
            pair_idx = pair_idx + 1;
            
            if pair_idx <= length(pair_vector)
                p_val = pair_vector(pair_idx);
                
                % Set symmetric values
                if ~isnan(p_val)
                    p_same_matrix(sess_i, sess_j) = p_val;
                    p_same_matrix(sess_j, sess_i) = p_val;
                end
            end
        end
    end
end
%% ========================================================================
%% VISUALIZATION FUNCTIONS (UNCHANGED)
%% ========================================================================

function fig_handle = visualize_field_of_view(mean_img, mean_img_enhanced, subject_id, session, options)
    fig_name = sprintf('Subject_%d_Session_%d_FOV', subject_id, session);
    fig_handle = figure('Position', [100, 100, 1200, 800], 'Name', fig_name, 'Visible', get_visibility(options));
    
    subplot(2, 2, 1);
    imshow(mean_img, []);
    title('Baseline Mean Image (Original)', 'FontSize', 14, 'FontWeight', 'bold');
    colorbar;
    
    subplot(2, 2, 2);
    mean_img_normalized = mat2gray(mean_img);
    mean_img_adj = imadjust(mean_img_normalized, stretchlim(mean_img_normalized, [0.01 0.99]));
    imshow(mean_img_adj);
    title('Baseline Mean Image (Contrast Enhanced)', 'FontSize', 14, 'FontWeight', 'bold');
    colorbar;
    
    subplot(2, 2, 3);
    imshow(mean_img_enhanced, []);
    title('Enhanced Mean Image (Original)', 'FontSize', 14, 'FontWeight', 'bold');
    colorbar;
    
    subplot(2, 2, 4);
    enhanced_normalized = mat2gray(mean_img_enhanced);
    enhanced_img_adj = imadjust(enhanced_normalized, stretchlim(enhanced_normalized, [0.01 0.99]));
    imshow(enhanced_img_adj);
    title('Enhanced Mean Image (Contrast Adjusted)', 'FontSize', 14, 'FontWeight', 'bold');
    colorbar;
    
    sgtitle(sprintf('Subject %d - Session %d - Field of View', subject_id, session), 'FontSize', 16, 'FontWeight', 'bold');
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_Sess%d_FOV', subject_id, session));
    end
end

function fig_handle = visualize_rois(mean_img, rois, subject_id, session, options)
    fig_name = sprintf('Subject_%d_Session_%d_ROI', subject_id, session);
    fig_handle = figure('Position', [150, 150, 1200, 600], 'Name', fig_name, 'Visible', get_visibility(options));
    
    img_normalized = mat2gray(mean_img);
    img_display = imadjust(img_normalized, stretchlim(img_normalized, [0.01 0.99]));
    
    subplot(1, 2, 1);
    imshow(img_display);
    hold on;
    scatter(rois.roi_centroid_x, rois.roi_centroid_y, 10, 'r', 'filled', 'MarkerEdgeColor', 'k');
    title('ROIs - Centroids', 'FontSize', 14, 'FontWeight', 'bold');
    hold off;
    
    subplot(1, 2, 2);
    imshow(img_display);
    hold on;
    
    for i = 1:length(rois.roi_number_uid)
        if i <= length(rois.roi_x_pix) && i <= length(rois.roi_y_pix)
            x_coords = double(rois.roi_x_pix{i});
            y_coords = double(rois.roi_y_pix{i});
            
            if ~isempty(x_coords) && ~isempty(y_coords) && length(x_coords) >= 3
                try
                    boundary_idx = boundary(x_coords, y_coords, 1);
                    plot(x_coords(boundary_idx), y_coords(boundary_idx), 'r-', 'LineWidth', 1.5);
                catch
                    try
                        k = convhull(x_coords, y_coords);
                        plot(x_coords(k), y_coords(k), 'r-', 'LineWidth', 1.5);
                    catch
                        continue;
                    end
                end
            end
        end
    end
    
    title('ROIs with Red Contours', 'FontSize', 14, 'FontWeight', 'bold');
    hold off;
    
    sgtitle(sprintf('Subject %d - Session %d - ROI Visualization', subject_id, session), 'FontSize', 16, 'FontWeight', 'bold');
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_Sess%d_ROI', subject_id, session));
    end
end

function fig_handle = visualize_rois_probability(mean_img_enhanced, rois, subject_id, session, options)
    fig_name = sprintf('Subject_%d_Session_%d_ROI_Probability', subject_id, session);
    fig_handle = figure('Position', [300, 300, 800, 600], 'Name', fig_name, 'Visible', get_visibility(options));
    
    bg_rgb = repmat(mat2gray(mean_img_enhanced), [1 1 3]);
    imshow(bg_rgb);
    hold on;
    axis on;
    axis equal tight;
    
    cmap = [linspace(1,0,256)', linspace(0,1,256)', zeros(256,1)];
    
    for i = 1:length(rois.roi_number_uid)
        if i <= length(rois.roi_x_pix) && i <= length(rois.roi_y_pix)
            x = double(rois.roi_x_pix{i});
            y = double(rois.roi_y_pix{i});
            
            if isempty(x) || isempty(y) || length(x) < 3
                continue;
            end
            
            try
                k = boundary(x, y, 1);
                x_contour = x(k);
                y_contour = y(k);
            catch
                if length(x) < 3
                    continue;
                end
                try
                    k = convhull(x, y);
                    x_contour = x(k);
                    y_contour = y(k);
                catch
                    continue;
                end
            end
            
            prob = rois.probability(i);
            idx = max(1, min(256, round(prob*255 + 1)));
            color = cmap(idx, :);
            
            plot(x_contour, y_contour, 'Color', color, 'LineWidth', 1.5);
        end
    end
    
    colormap(gca, cmap);
    caxis([0 1]);
    cb = colorbar;
    ylabel(cb, 'P(Cell)', 'FontSize', 12);
    
    title(sprintf('Subject %d - Session %d - ROI Contours by Cell Probability', subject_id, session), ...
          'FontSize', 14, 'FontWeight', 'bold');
    hold off;
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_Sess%d_ROI_Probability', subject_id, session));
    end
end

function fig_handle = visualize_simple_rois(mean_img_enhanced, rois, subject_id, session, options)
    fig_name = sprintf('Subject_%d_Session_%d_SimpleROI', subject_id, session);
    fig_handle = figure('Position', [250, 250, 800, 600], 'Name', fig_name, 'Visible', get_visibility(options));
    
    imshow(mean_img_enhanced, []);
    hold on;
    
    for i = 1:length(rois.roi_number_uid)
        if i <= length(rois.roi_x_pix) && i <= length(rois.roi_y_pix)
            x_coords = rois.roi_x_pix{i};
            y_coords = rois.roi_y_pix{i};
            
            if ~isempty(x_coords) && ~isempty(y_coords)
                scatter(x_coords, y_coords, 1, 'r', 'filled');
            end
        end
    end
    
    title(sprintf('Subject %d - Session %d - Simple ROI Contours', subject_id, session), 'FontSize', 14, 'FontWeight', 'bold');
    hold off;
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_Sess%d_SimpleROI', subject_id, session));
    end
end

function fig_handle = visualize_cutoff_image(cell_tensor, subject_id, session, options, n_kept)
    fig_name = sprintf('Subject_%d_Session_%d_Cutoff', subject_id, session);
    fig_handle = figure('Position', [200, 200, 800, 600], 'Name', fig_name, 'Visible', get_visibility(options));
    
    cutoff = mean(cell_tensor, 1);
    cutoff = reshape(cutoff, size(cell_tensor, 2), size(cell_tensor, 3));
    
    cutoff_normalized = mat2gray(cutoff);
    img_display = imadjust(cutoff_normalized, stretchlim(cutoff_normalized, [0.01 0.99]));
    
    imshow(img_display);
    title(sprintf('Subject %d - Session %d - Cut Cells Pixels (N=%d ROIs)', subject_id, session, n_kept), ...
          'FontSize', 14, 'FontWeight', 'bold');
    colorbar;
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_Sess%d_Cutoff', subject_id, session));
    end
end

%% ========================================================================
%% COMPARISON VISUALIZATION FUNCTIONS (UNCHANGED)
%% ========================================================================

function fig_handle = compare_sessions_contours(results, subject_id, options)
    sessions = [results.session];
    [sessions_sorted, sort_idx] = sort(sessions);
    n_sessions = length(sessions_sorted);
    
    fig_name = sprintf('Subject_%d_ContourComparison', subject_id);
    fig_handle = figure('Position', [100, 100, 400*n_sessions, 400], 'Name', fig_name, 'Visible', get_visibility(options));
    
    for i = 1:n_sessions
        result = results(sort_idx(i));
        
        subplot(1, n_sessions, i);
        
        img_normalized = mat2gray(result.mean_img_enhanced);
        img_display = imadjust(img_normalized, stretchlim(img_normalized, [0.01 0.99]));
        imshow(img_display);
        hold on;
        
        for j = 1:length(result.rois.roi_number_uid)
            if j <= length(result.rois.roi_x_pix) && j <= length(result.rois.roi_y_pix)
                x_coords = double(result.rois.roi_x_pix{j});
                y_coords = double(result.rois.roi_y_pix{j});
                
                if ~isempty(x_coords) && ~isempty(y_coords) && length(x_coords) >= 3
                    try
                        boundary_idx = boundary(x_coords, y_coords, 1);
                        plot(x_coords(boundary_idx), y_coords(boundary_idx), 'r-', 'LineWidth', 1.5);
                    catch
                        try
                            k = convhull(x_coords, y_coords);
                            plot(x_coords(k), y_coords(k), 'r-', 'LineWidth', 1.5);
                        catch
                            continue;
                        end
                    end
                end
            end
        end
        
        title(sprintf('Session %d', sessions_sorted(i)), 'FontSize', 12, 'FontWeight', 'bold');
        hold off;
    end
    
    sgtitle(sprintf('Subject %d - ROI Contours Comparison', subject_id), 'FontSize', 16, 'FontWeight', 'bold');
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_ContourComparison', subject_id));
    end
end

function fig_handle = compare_sessions_cutoff(results, subject_id, options)
    sessions = [results.session];
    [sessions_sorted, sort_idx] = sort(sessions);
    n_sessions = length(sessions_sorted);
    
    fig_name = sprintf('Subject_%d_CutoffComparison', subject_id);
    fig_handle = figure('Position', [100, 100, 400*n_sessions, 400], 'Name', fig_name, 'Visible', get_visibility(options));
    
    for i = 1:n_sessions
        result = results(sort_idx(i));
        
        subplot(1, n_sessions, i);
        
        cutoff = mean(result.cell_tensor, 1);
        cutoff = reshape(cutoff, size(result.cell_tensor, 2), size(result.cell_tensor, 3));
        
        cutoff_normalized = mat2gray(cutoff);
        img_display = imadjust(cutoff_normalized, stretchlim(cutoff_normalized, [0.01 0.99]));
        
        imshow(img_display);
        title(sprintf('Session %d', sessions_sorted(i)), 'FontSize', 12, 'FontWeight', 'bold');
        colorbar;
    end
    
    sgtitle(sprintf('Subject %d - Cutoff Comparison', subject_id), 'FontSize', 16, 'FontWeight', 'bold');
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_CutoffComparison', subject_id));
    end
end

function fig_handle = compare_sessions_baseline(results, subject_id, options)
    sessions = [results.session];
    [sessions_sorted, sort_idx] = sort(sessions);
    n_sessions = length(sessions_sorted);

    fig_name = sprintf('Subject_%d_BaselineComparison', subject_id);
    fig_handle = figure('Position', [100, 100, 400*n_sessions, 400], 'Name', fig_name, 'Visible', get_visibility(options));

    for i = 1:n_sessions
        result = results(sort_idx(i));

        subplot(1, n_sessions, i);

        % Apply contrast adjustment to baseline mean image
        baseline_normalized = mat2gray(result.mean_img);
        img_display = imadjust(baseline_normalized, stretchlim(baseline_normalized, [0.01 0.99]));

        imshow(img_display);
        title(sprintf('Session %d', sessions_sorted(i)), 'FontSize', 12, 'FontWeight', 'bold');
        colorbar;
    end

    sgtitle(sprintf('Subject %d - Baseline Mean Images Comparison (Contrast Adjusted)', subject_id), 'FontSize', 16, 'FontWeight', 'bold');

    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_BaselineComparison', subject_id));
    end
end

function fig_handle = compare_sessions_enhanced(results, subject_id, options)
    sessions = [results.session];
    [sessions_sorted, sort_idx] = sort(sessions);
    n_sessions = length(sessions_sorted);
    
    fig_name = sprintf('Subject_%d_EnhancedComparison', subject_id);
    fig_handle = figure('Position', [100, 100, 400*n_sessions, 400], 'Name', fig_name, 'Visible', get_visibility(options));
    
    for i = 1:n_sessions
        result = results(sort_idx(i));
        
        subplot(1, n_sessions, i);
        
        enhanced_normalized = mat2gray(result.mean_img_enhanced);
        img_display = imadjust(enhanced_normalized, stretchlim(enhanced_normalized, [0.01 0.99]));
        
        imshow(img_display);
        title(sprintf('Session %d', sessions_sorted(i)), 'FontSize', 12, 'FontWeight', 'bold');
        colorbar;
    end
    
    sgtitle(sprintf('Subject %d - Enhanced Images Comparison', subject_id), 'FontSize', 16, 'FontWeight', 'bold');
    
    if options.save_figures
        save_figure(fig_handle, options.save_path, sprintf('S%d_EnhancedComparison', subject_id));
    end
end

function visibility = get_visibility(options)
    if options.show_figures
        visibility = 'on';
    else
        visibility = 'off';
    end
end

function save_figure(fig_handle, save_path, filename)
    saveas(fig_handle, fullfile(save_path, [filename '.png']));
    saveas(fig_handle, fullfile(save_path, [filename '.fig']));
end

%% ========================================================================
%% CELLREG PIPELINE - PART 2 (MODIFIED TO CALL EXPANDED TABLE FUNCTION)
%% ========================================================================

function run_cellreg_pipeline(file_names, params)
% RUN_CELLREG_PIPELINE - Execute the complete CellReg registration

    number_of_sessions = length(file_names);
    results_directory = params.results_directory;
    
    % FIX: Store session numbers for proper labeling
    session_numbers = params.sessions;
    
    % FIX: Suppress progress bar clutter in diary
    feature('DefaultCharacterSet', 'UTF-8');
    
    % Ensure results directory exists first
    if ~exist(results_directory, 'dir')
        mkdir(results_directory);
    end
    
    % Then create figures directory
    figures_directory = fullfile(results_directory, 'Figures');
    if ~exist(figures_directory, 'dir')
        mkdir(figures_directory);
    end
    
    figures_visibility = params.figures_visibility;
    memory_efficient_run = params.memory_efficient_run;
    
    if memory_efficient_run
        temp_dir = fullfile(figures_directory, 'temp');
        if ~exist(temp_dir, 'dir')
            mkdir(temp_dir);
        end
    end
    
    %% Stage 1 - Loading the spatial footprints
    fprintf('Stage 1 - Loading sessions\n');
    microns_per_pixel = params.microns_per_pixel;
    
    if memory_efficient_run
        spatial_footprints = file_names;
    else
        [spatial_footprints, ~] = load_multiple_sessions(file_names);
    end
    
    [footprints_projections] = compute_footprints_projections(spatial_footprints);
    plot_all_sessions_projections(footprints_projections, figures_directory, figures_visibility);
    fprintf('Done\n');
    clear footprints_projections
    
    %% Stage 2 - Aligning all sessions
    fprintf('Stage 2 - Aligning sessions\n');
    
    if memory_efficient_run
        [normalized_spatial_footprints] = normalize_spatial_footprints(spatial_footprints, temp_dir);
    else
        [normalized_spatial_footprints] = normalize_spatial_footprints(spatial_footprints);
    end
    clear spatial_footprints
    
    [adjusted_spatial_footprints, adjusted_FOV, adjusted_x_size, adjusted_y_size, adjustment_zero_padding] = ...
        adjust_FOV_size(normalized_spatial_footprints);
    clear normalized_spatial_footprints

    % Suppress diary during centroid calculations to avoid progress bar clutter
    diary off;
    [adjusted_footprints_projections] = compute_footprints_projections(adjusted_spatial_footprints);
    [centroid_locations] = compute_centroid_locations(adjusted_spatial_footprints, microns_per_pixel);
    [centroid_projections] = compute_centroids_projections(centroid_locations, adjusted_spatial_footprints);
    diary on;
    fprintf('  Computed centroids and projections\n');

    % Alignment
    alignment_type = params.alignment_type;
    reference_session_index = params.reference_session_index;
    use_parallel_processing = params.use_parallel_processing;
    sufficient_correlation_centroids = params.sufficient_correlation_centroids;
    sufficient_correlation_footprints = params.sufficient_correlation_footprints;
    
    % Suppress alignment warnings
    warning('off', 'all');

    % Suppress diary during alignment to avoid progress bar clutter
    diary off;

    if strcmp(alignment_type, 'Translations and Rotations')
        maximal_rotation = params.maximal_rotation;
        [spatial_footprints_corrected, centroid_locations_corrected, ...
         footprints_projections_corrected, centroid_projections_corrected, ...
         maximal_cross_correlation, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, reference_session_index, alignment_type, ...
                        sufficient_correlation_centroids, sufficient_correlation_footprints, ...
                        use_parallel_processing, maximal_rotation);
    elseif strcmp(alignment_type, 'Non-rigid')
        transformation_smoothness = params.transformation_smoothness;
        [spatial_footprints_corrected, centroid_locations_corrected, ...
         footprints_projections_corrected, centroid_projections_corrected, ...
         maximal_cross_correlation, alignment_translations, overlapping_FOV, ...
         displacement_fields] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, reference_session_index, alignment_type, ...
                        sufficient_correlation_centroids, sufficient_correlation_footprints, ...
                        use_parallel_processing, transformation_smoothness);
    else
        [spatial_footprints_corrected, centroid_locations_corrected, ...
         footprints_projections_corrected, centroid_projections_corrected, ...
         maximal_cross_correlation, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, reference_session_index, alignment_type, ...
                        sufficient_correlation_centroids, sufficient_correlation_footprints, ...
                        use_parallel_processing);
    end

    % Resume diary after alignment
    diary on;

    warning('on', 'all');

    % FIX: Custom data quality evaluation with size mismatch handling
    fprintf('  Evaluating data quality...\n');
    
    if iscell(spatial_footprints_corrected)
        num_sessions = length(spatial_footprints_corrected);
    else
        num_sessions = 1;
    end
    
    % Compute all_projections_correlations with safe correlation
    all_projections_correlations = zeros(num_sessions);
    
    for n = 1:num_sessions
        for k = 1:num_sessions
            if n == k
                all_projections_correlations(n, k) = 1;
            else
                proj_n = footprints_projections_corrected{n};
                proj_k = footprints_projections_corrected{k};
                
                [h_n, w_n] = size(proj_n);
                [h_k, w_k] = size(proj_k);
                
                if h_n == h_k && w_n == w_k
                    all_projections_correlations(n, k) = corr2(proj_n, proj_k);
                else
                    h_min = min(h_n, h_k);
                    w_min = min(w_n, w_k);
                    proj_n_crop = proj_n(1:h_min, 1:w_min);
                    proj_k_crop = proj_k(1:h_min, 1:w_min);
                    all_projections_correlations(n, k) = corr2(proj_n_crop, proj_k_crop);
                end
            end
        end
    end
    
        % Count number of cells per session
    number_of_cells_per_session = zeros(1, num_sessions);
    for i = 1:num_sessions
        if iscell(spatial_footprints_corrected)
            if ischar(spatial_footprints_corrected{i}) || isstring(spatial_footprints_corrected{i})
                % It's a filename - load and count
                temp_data = load(spatial_footprints_corrected{i});
                if isfield(temp_data, 'footprint')
                    if iscell(temp_data.footprint)
                        number_of_cells_per_session(i) = length(temp_data.footprint);
                    elseif isnumeric(temp_data.footprint) && ndims(temp_data.footprint) == 3
                        number_of_cells_per_session(i) = size(temp_data.footprint, 1);
                    else
                        number_of_cells_per_session(i) = 1;
                    end
                elseif isfield(temp_data, 'footprints')
                    if iscell(temp_data.footprints)
                        number_of_cells_per_session(i) = length(temp_data.footprints);
                    elseif isnumeric(temp_data.footprints) && ndims(temp_data.footprints) == 3
                        number_of_cells_per_session(i) = size(temp_data.footprints, 1);
                    else
                        number_of_cells_per_session(i) = 1;
                    end
                else
                    % Fallback: try to infer from any numeric array
                    fields = fieldnames(temp_data);
                    for f = 1:length(fields)
                        if isnumeric(temp_data.(fields{f})) && ndims(temp_data.(fields{f})) == 3
                            number_of_cells_per_session(i) = size(temp_data.(fields{f}), 1);
                            break;
                        elseif iscell(temp_data.(fields{f}))
                            number_of_cells_per_session(i) = length(temp_data.(fields{f}));
                            break;
                        end
                    end
                end
            elseif iscell(spatial_footprints_corrected{i})
                % It's already a cell array
                number_of_cells_per_session(i) = length(spatial_footprints_corrected{i});
            elseif isnumeric(spatial_footprints_corrected{i}) && ndims(spatial_footprints_corrected{i}) == 3
                % It's a 3D numeric array
                number_of_cells_per_session(i) = size(spatial_footprints_corrected{i}, 1);
            end
        elseif isnumeric(spatial_footprints_corrected) && ndims(spatial_footprints_corrected) == 3
            % It's a single 3D array for all sessions
            number_of_cells_per_session(i) = size(spatial_footprints_corrected, 1);
        end
    end
    
    fprintf('    Cells per session: [%s]\n', num2str(number_of_cells_per_session));
    fprintf('    Data quality evaluation complete.\n');
    
    % Plot alignment results
    try
        if strcmp(alignment_type, 'Non-rigid')
            plot_alignment_results(adjusted_spatial_footprints, centroid_locations, ...
                                  spatial_footprints_corrected, centroid_locations_corrected, ...
                                  adjusted_footprints_projections, footprints_projections_corrected, ...
                                  reference_session_index, all_projections_correlations, ...
                                  maximal_cross_correlation, alignment_translations, overlapping_FOV, ...
                                  alignment_type, number_of_cells_per_session, figures_directory, ...
                                  figures_visibility, displacement_fields);
        else
            plot_alignment_results(adjusted_spatial_footprints, centroid_locations, ...
                                  spatial_footprints_corrected, centroid_locations_corrected, ...
                                  adjusted_footprints_projections, footprints_projections_corrected, ...
                                  reference_session_index, all_projections_correlations, ...
                                  maximal_cross_correlation, alignment_translations, overlapping_FOV, ...
                                  alignment_type, number_of_cells_per_session, figures_directory, ...
                                  figures_visibility);
        end
    catch ME
        warning('Failed to generate alignment plots: %s', ME.message);
    end
    
    if use_parallel_processing
        delete(gcp);
    end
    fprintf('Done\n');
    
    %% Stage 3 - Probabilistic modeling
    fprintf('Stage 3 - Calculating probabilistic model\n');
    
    maximal_distance = params.maximal_distance;
    normalized_maximal_distance = maximal_distance / microns_per_pixel;
    p_same_certainty_threshold = params.p_same_certainty_threshold;
    
    [number_of_bins, centers_of_bins] = estimate_number_of_bins(adjusted_spatial_footprints, normalized_maximal_distance);

    % Suppress diary during compute_data_distribution to avoid session-by-session logging clutter
    diary off;
    [all_to_all_indexes, all_to_all_spatial_correlations, all_to_all_centroid_distances, ...
     neighbors_spatial_correlations, neighbors_centroid_distances, neighbors_x_displacements, ...
     neighbors_y_displacements, NN_spatial_correlations, NNN_spatial_correlations, ...
     NN_centroid_distances, NNN_centroid_distances] = ...
        compute_data_distribution(spatial_footprints_corrected, centroid_locations_corrected, ...
                                 normalized_maximal_distance);

    plot_x_y_displacements(neighbors_x_displacements, neighbors_y_displacements, ...
                          microns_per_pixel, normalized_maximal_distance, number_of_bins, ...
                          centers_of_bins, figures_directory, figures_visibility);

    [centroid_distances_model_parameters, p_same_given_centroid_distance, ...
     centroid_distances_distribution, centroid_distances_model_same_cells, ...
     centroid_distances_model_different_cells, centroid_distances_model_weighted_sum, ...
     MSE_centroid_distances_model, centroid_distance_intersection] = ...
        compute_centroid_distances_model(neighbors_centroid_distances, microns_per_pixel, centers_of_bins);

    [spatial_correlations_model_parameters, p_same_given_spatial_correlation, ...
     spatial_correlations_distribution, spatial_correlations_model_same_cells, ...
     spatial_correlations_model_different_cells, spatial_correlations_model_weighted_sum, ...
     MSE_spatial_correlations_model, spatial_correlation_intersection] = ...
        compute_spatial_correlations_model(neighbors_spatial_correlations, centers_of_bins);

    [p_same_centers_of_bins, uncertain_fraction_centroid_distances, ...
     cdf_p_same_centroid_distances, false_positive_per_distance_threshold, ...
     true_positive_per_distance_threshold, uncertain_fraction_spatial_correlations, ...
     cdf_p_same_spatial_correlations, false_positive_per_correlation_threshold, ...
     true_positive_per_correlation_threshold] = ...
        estimate_registration_accuracy(p_same_certainty_threshold, neighbors_centroid_distances, ...
                                      centroid_distances_model_same_cells, ...
                                      centroid_distances_model_different_cells, ...
                                      p_same_given_centroid_distance, centers_of_bins, ...
                                      neighbors_spatial_correlations, ...
                                      spatial_correlations_model_same_cells, ...
                                      spatial_correlations_model_different_cells, ...
                                      p_same_given_spatial_correlation);

    [best_model_string] = choose_best_model(MSE_centroid_distances_model, ...
                                           centroid_distances_model_same_cells, ...
                                           centroid_distances_model_different_cells, ...
                                           p_same_given_centroid_distance, ...
                                           MSE_spatial_correlations_model, ...
                                           spatial_correlations_model_same_cells, ...
                                           spatial_correlations_model_different_cells, ...
                                           p_same_given_spatial_correlation);

    plot_models(centroid_distances_model_parameters, NN_centroid_distances, ...
               NNN_centroid_distances, centroid_distances_distribution, ...
               centroid_distances_model_same_cells, centroid_distances_model_different_cells, ...
               centroid_distances_model_weighted_sum, centroid_distance_intersection, ...
               centers_of_bins, microns_per_pixel, normalized_maximal_distance, ...
               figures_directory, figures_visibility, spatial_correlations_model_parameters, ...
               NN_spatial_correlations, NNN_spatial_correlations, ...
               spatial_correlations_distribution, spatial_correlations_model_same_cells, ...
               spatial_correlations_model_different_cells, ...
               spatial_correlations_model_weighted_sum, spatial_correlation_intersection);

    plot_estimated_registration_accuracy(p_same_centers_of_bins, p_same_certainty_threshold, ...
                                        p_same_given_centroid_distance, ...
                                        centroid_distances_distribution, ...
                                        cdf_p_same_centroid_distances, ...
                                        uncertain_fraction_centroid_distances, ...
                                        true_positive_per_distance_threshold, ...
                                        false_positive_per_distance_threshold, ...
                                        centers_of_bins, normalized_maximal_distance, ...
                                        microns_per_pixel, figures_directory, figures_visibility, ...
                                        p_same_given_spatial_correlation, ...
                                        spatial_correlations_distribution, ...
                                        cdf_p_same_spatial_correlations, ...
                                        uncertain_fraction_spatial_correlations, ...
                                        true_positive_per_correlation_threshold, ...
                                        false_positive_per_correlation_threshold);

    [all_to_all_p_same_centroid_distance_model, all_to_all_p_same_spatial_correlation_model] = ...
        compute_p_same(all_to_all_centroid_distances, p_same_given_centroid_distance, ...
                      centers_of_bins, all_to_all_spatial_correlations, ...
                      p_same_given_spatial_correlation);
    diary on;

    fprintf('Done\n');
    
    %% Stage 4 - Initial registration
    fprintf('Stage 4 - Performing initial registration\n');
    
    initial_registration_type = params.initial_registration_type;
    
    if strcmp(initial_registration_type, 'Spatial correlation')
        if exist('spatial_correlation_intersection', 'var')
            initial_threshold = spatial_correlation_intersection;
        else
            initial_threshold = 0.65;
        end
        [cell_to_index_map, registered_cells_spatial_correlations, ...
         non_registered_cells_spatial_correlations] = ...
            initial_registration_spatial_correlations(normalized_maximal_distance, ...
                                                     initial_threshold, ...
                                                     spatial_footprints_corrected, ...
                                                     centroid_locations_corrected);
        plot_initial_registration(cell_to_index_map, number_of_bins, ...
                                 spatial_footprints_corrected, initial_registration_type, ...
                                 figures_directory, figures_visibility, ...
                                 registered_cells_spatial_correlations, ...
                                 non_registered_cells_spatial_correlations);
    else
        if exist('centroid_distance_intersection', 'var')
            initial_threshold = centroid_distance_intersection;
        else
            initial_threshold = 5;
        end
        normalized_distance_threshold = initial_threshold / microns_per_pixel;
        [cell_to_index_map, registered_cells_centroid_distances, ...
         non_registered_cells_centroid_distances] = ...
            initial_registration_centroid_distances(normalized_maximal_distance, ...
                                                   normalized_distance_threshold, ...
                                                   centroid_locations_corrected);
        plot_initial_registration(cell_to_index_map, number_of_bins, ...
                                 spatial_footprints_corrected, initial_registration_type, ...
                                 figures_directory, figures_visibility, ...
                                 registered_cells_centroid_distances, ...
                                 non_registered_cells_centroid_distances, ...
                                 microns_per_pixel, normalized_maximal_distance);
    end
    
    fprintf('%d cells were found\n', size(cell_to_index_map, 1));
    fprintf('Done\n');

    %% Stage 5 - Final registration
    fprintf('Stage 5 - Performing final registration\n');
    
    registration_approach = params.registration_approach;
    if strcmp(params.model_type, 'best_model_string')
        model_type = best_model_string;
    else
        model_type = params.model_type;
    end
    p_same_threshold = params.p_same_threshold;
    
    transform_data = false;
    if strcmp(registration_approach, 'Simple threshold')
        if strcmp(model_type, 'Spatial correlation')
            if exist('spatial_correlation_intersection', 'var')
                final_threshold = spatial_correlation_intersection;
            else
                final_threshold = 0.65;
            end
        elseif strcmp(model_type, 'Centroid distance')
            if exist('centroid_distance_intersection', 'var')
                final_threshold = centroid_distance_intersection;
            else
                final_threshold = 5;
            end
            normalized_distance_threshold = (maximal_distance - final_threshold) / maximal_distance;
            transform_data = true;
        end
    else
        final_threshold = p_same_threshold;
    end
    
    % Clustering
    if strcmp(registration_approach, 'Probabilistic')
        if strcmp(model_type, 'Spatial correlation')
            [optimal_cell_to_index_map, registered_cells_centroids, cell_scores, ...
             cell_scores_positive, cell_scores_negative, cell_scores_exclusive, ...
             p_same_registered_pairs] = ...
                cluster_cells(cell_to_index_map, all_to_all_p_same_spatial_correlation_model, ...
                             all_to_all_indexes, normalized_maximal_distance, p_same_threshold, ...
                             centroid_locations_corrected, registration_approach, transform_data);
        else
            [optimal_cell_to_index_map, registered_cells_centroids, cell_scores, ...
             cell_scores_positive, cell_scores_negative, cell_scores_exclusive, ...
             p_same_registered_pairs] = ...
                cluster_cells(cell_to_index_map, all_to_all_p_same_centroid_distance_model, ...
                             all_to_all_indexes, normalized_maximal_distance, p_same_threshold, ...
                             centroid_locations_corrected, registration_approach, transform_data);
        end
        plot_cell_scores(cell_scores_positive, cell_scores_negative, cell_scores_exclusive, ...
                        cell_scores, p_same_registered_pairs, figures_directory, figures_visibility);
    else
        if strcmp(model_type, 'Spatial correlation')
            [optimal_cell_to_index_map, registered_cells_centroids] = ...
                cluster_cells(cell_to_index_map, all_to_all_spatial_correlations, ...
                             all_to_all_indexes, normalized_maximal_distance, final_threshold, ...
                             centroid_locations_corrected, registration_approach, transform_data);
        else
            [optimal_cell_to_index_map, registered_cells_centroids] = ...
                cluster_cells(cell_to_index_map, all_to_all_centroid_distances, ...
                             all_to_all_indexes, normalized_maximal_distance, ...
                             normalized_distance_threshold, centroid_locations_corrected, ...
                             registration_approach, transform_data);
        end
    end
    
    [is_in_overlapping_FOV] = check_if_in_overlapping_FOV(registered_cells_centroids, overlapping_FOV);
    
    fprintf('  Plotting final registered projections...\n');
    nonzero_counts = sum(optimal_cell_to_index_map ~= 0, 2);
    total_cells_all_sessions = sum(nonzero_counts == number_of_sessions);
    
    plot_all_registered_projections(spatial_footprints_corrected, optimal_cell_to_index_map, ...
                                   figures_directory, figures_visibility);
    
   try
        all_figs = findall(0, 'Type', 'figure');
        if ~isempty(all_figs)
            fig = all_figs(1);
            % FIXED: Don't call figure(fig) when visibility is off - it makes the figure visible
            if strcmp(figures_visibility, 'on')
                figure(fig);
            else
                set(0, 'CurrentFigure', fig);  % Select figure without making it visible
            end

            % FIXED: Update main title without trying to adjust Position
            % sgtitle returns an annotation object, not a text object with Position property
            sgtitle(sprintf('Stage 5 - Projections - Final Registration (Total cells in all sessions: %d)', ...
                   total_cells_all_sessions), ...
                   'FontSize', 16, 'FontWeight', 'bold');
            
            % Adjust subplot positions to make room for title
            axs = findall(fig, 'Type', 'axes');
            for ax_idx = 1:length(axs)
                if isvalid(axs(ax_idx))
                    pos = get(axs(ax_idx), 'Position');
                    % Move subplots down slightly to make room for title
                    set(axs(ax_idx), 'Position', [pos(1), pos(2)-0.02, pos(3), pos(4)]);
                end
            end
            
            % Add cell count text to each subplot
            for i = 1:min(number_of_sessions, length(axs))
                ax_idx = length(axs) - i + 1;
                if ax_idx > 0 && ax_idx <= length(axs) && isvalid(axs(ax_idx))
                    axes(axs(ax_idx));
                    if i <= length(number_of_cells_per_session)
                        cells_in_session = number_of_cells_per_session(i);
                        text(0.05, 0.95, sprintf('n=%d cells', cells_in_session), ...
                             'Units', 'normalized', 'VerticalAlignment', 'top', ...
                             'HorizontalAlignment', 'left', 'FontSize', 11, ...
                             'FontWeight', 'bold', 'Color', 'white', ...
                             'BackgroundColor', [0 0 0 0.6], ...
                             'EdgeColor', 'white', 'LineWidth', 1.5, 'Margin', 3);
                    end
                end
            end
            
            saveas(fig, fullfile(figures_directory, 'Stage_5_all_registered_projections_enhanced.png'));
            saveas(fig, fullfile(figures_directory, 'Stage_5_all_registered_projections_enhanced.fig'));
        end
    catch ME
        fprintf('  Warning: Could not enhance final registration plot: %s\n', ME.message);
    end

    
    %% Save results
    fprintf('Saving results\n');
    
    if memory_efficient_run
        fprintf('  Saving corrected footprints with mean images...\n');
        for file_n = 1:length(spatial_footprints_corrected)
            split_name = strsplit(spatial_footprints_corrected{file_n}, filesep);
            f_name = split_name{end};
            
            % Load footprints
            footprints = get_spatial_footprints(spatial_footprints_corrected{file_n});
            footprints = footprints.load_footprints;
            footprints = footprints.footprints;
            footprint = mat_to_sparse_cell(footprints);
            
            % Get corresponding mean_img_enhanced (if available)
            mean_img_enhanced = [];
            
            % Save path
            spatial_footprints_corrected{file_n} = fullfile(results_directory, f_name);
            
            % Save with mean_img_enhanced if available
            if ~isempty(mean_img_enhanced)
                save(fullfile(results_directory, f_name), 'footprint', 'mean_img_enhanced');
            else
                save(fullfile(results_directory, f_name), 'footprint');
            end
        end
    end
    
    cell_registered_struct = struct;
    cell_registered_struct.cell_to_index_map = optimal_cell_to_index_map;
    if strcmp(registration_approach, 'Probabilistic')
        cell_registered_struct.cell_scores = cell_scores';
        cell_registered_struct.true_positive_scores = cell_scores_positive';
        cell_registered_struct.true_negative_scores = cell_scores_negative';
        cell_registered_struct.exclusivity_scores = cell_scores_exclusive';
        cell_registered_struct.p_same_registered_pairs = p_same_registered_pairs';
    end
    cell_registered_struct.is_cell_in_overlapping_FOV = is_in_overlapping_FOV';
    cell_registered_struct.registered_cells_centroids = registered_cells_centroids';
    cell_registered_struct.centroid_locations_corrected = centroid_locations_corrected';
    cell_registered_struct.spatial_footprints_corrected = spatial_footprints_corrected';
    cell_registered_struct.alignment_x_translations = alignment_translations(1, :);
    cell_registered_struct.alignment_y_translations = alignment_translations(2, :);
    if strcmp(alignment_type, 'Translations and Rotations')
        cell_registered_struct.alignment_rotations = alignment_translations(3, :);
    end
    cell_registered_struct.adjustment_x_zero_padding = adjustment_zero_padding(1, :);
    cell_registered_struct.adjustment_y_zero_padding = adjustment_zero_padding(2, :);
    
    save(fullfile(results_directory, ['cellRegistered_' datestr(clock, 'yyyymmdd_HHMMss') '.mat']), ...
         'cell_registered_struct', '-v7.3');
    
    % Save log file
    comments = '';
    if strcmp(registration_approach, 'Probabilistic')
        if strcmp(model_type, 'Spatial correlation')
            save_log_file(results_directory, file_names, microns_per_pixel, adjusted_x_size, ...
                         adjusted_y_size, alignment_type, reference_session_index, maximal_distance, ...
                         number_of_bins, initial_registration_type, initial_threshold, ...
                         registration_approach, model_type, final_threshold, optimal_cell_to_index_map, ...
                         cell_registered_struct, comments, uncertain_fraction_spatial_correlations, ...
                         false_positive_per_correlation_threshold, ...
                         true_positive_per_correlation_threshold, MSE_spatial_correlations_model);
        else
            save_log_file(results_directory, file_names, microns_per_pixel, adjusted_x_size, ...
                         adjusted_y_size, alignment_type, reference_session_index, maximal_distance, ...
                         number_of_bins, initial_registration_type, initial_threshold, ...
                         registration_approach, model_type, final_threshold, optimal_cell_to_index_map, ...
                         cell_registered_struct, comments, uncertain_fraction_centroid_distances, ...
                         false_positive_per_distance_threshold, true_positive_per_distance_threshold, ...
                         MSE_centroid_distances_model);
        end
    else
        save_log_file(results_directory, file_names, microns_per_pixel, adjusted_x_size, ...
                     adjusted_y_size, alignment_type, reference_session_index, maximal_distance, ...
                     number_of_bins, initial_registration_type, initial_threshold, ...
                     registration_approach, model_type, final_threshold, optimal_cell_to_index_map, ...
                     cell_registered_struct, comments);
    end
    
    fprintf('%d cells were found\n', size(optimal_cell_to_index_map, 1));
    fprintf('Done\n');

    % Plot histogram
    fig = figure;
    histogram(nonzero_counts);
    xlabel('Number of sessions');
    ylabel('Number of cells');
    title(sprintf('Histogram of occurrences per cell (threshold=%.2f, resolution=%.2f, max distance=%.2f)', ...
                  p_same_threshold, microns_per_pixel, maximal_distance));
    saveas(fig, fullfile(results_directory, sprintf('Histogram_threshold%.2f_resolution%.2f_maxdist%.2f.png', ...
                                                    p_same_threshold, microns_per_pixel, maximal_distance)));
    close(fig);
    
    % FIX: Generate zoomed contour comparison with session numbers
    % Load enhanced mean images for zoomed comparisons
    fprintf('\n  Loading enhanced mean images for zoomed visualizations...\n');
    mean_images = cell(1, number_of_sessions);
    
    for i = 1:number_of_sessions
        try
            % Load from the original file_names (not corrected footprints)
            data = load(file_names{i});
            
            if isfield(data, 'mean_img')
                mean_images{i} = data.mean_img;
                fprintf('    Session %d: Loaded mean_img (%dx%d)\n', ...
                        i, size(mean_images{i}, 1), size(mean_images{i}, 2));
            else
                warning('Session %d: mean_img not found in file', i);
                mean_images{i} = [];
            end
        catch ME
            warning('Failed to load mean_img for session %d: %s', i, ME.message);
            mean_images{i} = [];
        end
    end
    
    fprintf('\nGenerating zoomed cell contour comparisons...\n');
    % Select cells appearing in 2+ sessions (not just all sessions)
    cells_multi_session = find(nonzero_counts >= 2);

    if ~isempty(cells_multi_session)
        zoom_dir = fullfile(figures_directory, 'Zoomed_Cell_Comparisons');
        if ~exist(zoom_dir, 'dir')
            mkdir(zoom_dir);
        end

        if strcmp(registration_approach, 'Probabilistic') && exist('p_same_registered_pairs', 'var')
            has_p_same = true;
        else
            has_p_same = false;
        end

        % Use user-specified n_zoomed parameter
        n_zoomed = min(params.n_zoomed, length(cells_multi_session));
        % Sample evenly across the range of cells
        if length(cells_multi_session) > n_zoomed
            sample_indices = round(linspace(1, length(cells_multi_session), n_zoomed));
        else
            sample_indices = 1:length(cells_multi_session);
        end

        fprintf('  Sampling %d cells from %d multi-session cells\n', n_zoomed, length(cells_multi_session));

        for i = 1:length(sample_indices)
            cell_idx = cells_multi_session(sample_indices(i));
            try
                if has_p_same
                    plot_zoomed_cell_comparison(cell_idx, optimal_cell_to_index_map, ...
                                               spatial_footprints_corrected, ...
                                               centroid_locations_corrected, ...
                                               zoom_dir, figures_visibility, ...
                                               p_same_registered_pairs, session_numbers, ...
                                               mean_images, params.roi_mappings, ...
                                               microns_per_pixel);
                else
                    plot_zoomed_cell_comparison(cell_idx, optimal_cell_to_index_map, ...
                                               spatial_footprints_corrected, ...
                                               centroid_locations_corrected, ...
                                               zoom_dir, figures_visibility, ...
                                               [], session_numbers, ...
                                               mean_images, params.roi_mappings, ...
                                               microns_per_pixel);
                end
            catch ME
                fprintf('  Warning: Failed to create zoomed comparison for cell %d: %s\n', cell_idx, ME.message);
            end
        end
        
        fprintf('Created %d zoomed cell comparisons in: %s\n', n_zoomed, zoom_dir);
    else
        fprintf('No cells found appearing in all sessions. Skipping zoomed comparison generation.\n');
    end

    % DEBUG: Create standalone P_same heatmap figures for testing
    if has_p_same && ~isempty(cells_multi_session)
        fprintf('\n=== DEBUG: Creating standalone P_same heatmap figures ===\n');

        debug_dir = fullfile(figures_directory, 'Debug_PSame_Heatmaps');
        if ~exist(debug_dir, 'dir')
            mkdir(debug_dir);
        end

        % Test with first 5 cells (or fewer if not enough cells)
        n_debug_cells = min(5, length(cells_multi_session));
        fprintf('  Testing P_same heatmaps for %d cells...\n', n_debug_cells);

        for i = 1:n_debug_cells
            cell_idx = cells_multi_session(i);
            cell_indices = optimal_cell_to_index_map(cell_idx, :);
            sessions_present = find(cell_indices > 0);
            n_sessions_present = length(sessions_present);

            if n_sessions_present >= 2
                try
                    % Extract P_same matrix
                    p_same_matrix = extract_p_same_for_cell(cell_idx, optimal_cell_to_index_map, ...
                                                           p_same_registered_pairs, sessions_present);

                    % Create session labels
                    session_labels = cell(1, n_sessions_present);
                    for s = 1:n_sessions_present
                        session_labels{s} = sprintf('S%d', session_numbers(sessions_present(s)));
                    end

                    % Create standalone figure
                    fig = figure('Position', [200, 200, 600, 500], 'Visible', figures_visibility);

                    imagesc(p_same_matrix);
                    set(gca, 'XTick', 1:n_sessions_present, 'XTickLabel', session_labels);
                    set(gca, 'YTick', 1:n_sessions_present, 'YTickLabel', session_labels);
                    xlabel('Session', 'FontSize', 12, 'FontWeight', 'bold');
                    ylabel('Session', 'FontSize', 12, 'FontWeight', 'bold');
                    title(sprintf('Cell %d - P(Same Cell) Matrix', cell_idx), ...
                          'FontSize', 14, 'FontWeight', 'bold');

                    colormap(jet);
                    c = colorbar;
                    c.Label.String = 'Probability';
                    c.Label.FontSize = 12;
                    caxis([0 1]);

                    % Add text annotations
                    for ii = 1:n_sessions_present
                        for jj = 1:n_sessions_present
                            if ~isnan(p_same_matrix(ii, jj))
                                if p_same_matrix(ii, jj) > 0.5
                                    text_color = 'white';
                                else
                                    text_color = 'black';
                                end
                                text(jj, ii, sprintf('%.3f', p_same_matrix(ii, jj)), ...
                                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                                     'FontSize', 10, 'Color', text_color, 'FontWeight', 'bold');
                            else
                                text(jj, ii, 'N/A', ...
                                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                                     'FontSize', 8, 'Color', 'black');
                            end
                        end
                    end

                    axis square;

                    % Save figure
                    filename = sprintf('DEBUG_Cell_%d_PSame_Heatmap.png', cell_idx);
                    saveas(fig, fullfile(debug_dir, filename));
                    close(fig);

                    fprintf('    Cell %d: P_same heatmap saved (sessions: [%s])\n', ...
                            cell_idx, sprintf('%d ', session_numbers(sessions_present)));

                catch ME
                    fprintf('    Warning: Failed to create P_same heatmap for cell %d: %s\n', ...
                            cell_idx, ME.message);
                end
            end
        end

        fprintf('  Created debug P_same heatmaps in: %s\n', debug_dir);
        fprintf('=== END DEBUG ===\n\n');
    end

   % Generate Venn diagram of shared cells
    fprintf('\nGenerating session overlap visualization...\n');
    try
        % Get subject_id from params
        if isfield(params, 'subject_id')
            subject_id = params.subject_id;
        else
            subject_id = [];
        end
        
        plot_session_venn_diagram(optimal_cell_to_index_map, figures_directory, ...
                                 figures_visibility, session_numbers, subject_id, nonzero_counts);
        fprintf('Created session overlap visualization\n');
    catch ME
        fprintf('  Warning: Failed to create session overlap visualization: %s\n', ME.message);
    end
    
%% MODIFIED: Create expanded registration table including filtered cells
if isfield(params, 'roi_mappings') && ~isempty(params.roi_mappings)
    create_expanded_registration_table(optimal_cell_to_index_map, ...
                                      params.roi_mappings, ...
                                      results_directory, ...
                                      params.session_numbers);
    
    % Create ROI-to-CellReg lookup table (loads p_same from cellRegistered file)
    create_roi_to_cellreg_lookup_tables(optimal_cell_to_index_map, ...
                                       params.roi_mappings, ...
                                       results_directory, ...
                                       params.session_numbers, ...
                                       params.subject_id);
else
    fprintf('\nWarning: ROI mappings not found in params. Skipping expanded table creation.\n');
end
    % Clean up
    if memory_efficient_run
        rmdir(temp_dir, 's');
    end
    
    fprintf('Cell registration completed successfully!\n');
    
    % Final summary
    fprintf('\n=== FINAL SUMMARY ===\n');
    fprintf('Total registered cells: %d\n', size(optimal_cell_to_index_map, 1));
    fprintf('Cells in all sessions: %d\n', sum(nonzero_counts == number_of_sessions));
    fprintf('Cells in 3+ sessions: %d\n', sum(nonzero_counts >= 3));
    fprintf('Results saved to: %s\n', results_directory);
    fprintf('Figures saved to: %s\n', figures_directory);
    fprintf('=====================\n');
    
end

%% ========================================================================
%% PART 3 - HELPER FUNCTIONS
%% ========================================================================

function plot_single_cell_heatmap(optimal_cell_to_index_map, centroid_locations_corrected, ...
                                 microns_per_pixel, figures_directory, file_names, ...
                                 cell_index, session_numbers, figures_visibility)
% PLOT_SINGLE_CELL_HEATMAP - Create heatmap with FIXED 0-5 micron colorbar
% MODIFIED: Added figures_visibility parameter to control display
    
    if nargin < 6
        nonzero_counts = sum(optimal_cell_to_index_map ~= 0, 2);
        valid_cells = find(nonzero_counts >= 3);
        if isempty(valid_cells)
            error('No cells found that appear in at least 3 sessions');
        end
        cell_index = valid_cells(1);
    end
    
    if nargin < 7
        session_numbers = 1:size(optimal_cell_to_index_map, 2);
    end
    
    if nargin < 8
        figures_visibility = 'on';  % Default to showing figures
    end
    
    num_sessions = size(optimal_cell_to_index_map, 2);
    
    % Create session labels using ACTUAL session numbers
    session_labels = cell(1, num_sessions);
    for i = 1:num_sessions
        session_labels{i} = sprintf('S%d', session_numbers(i));
    end
    
    % Initialize distance matrix
    euclidean_distances = NaN(num_sessions, num_sessions);
    
    % Calculate pairwise distances
    for session_i = 1:num_sessions
        for session_j = 1:num_sessions
            cell_i_idx = optimal_cell_to_index_map(cell_index, session_i);
            cell_j_idx = optimal_cell_to_index_map(cell_index, session_j);
            
            if isscalar(cell_i_idx) && isscalar(cell_j_idx) && cell_i_idx > 0 && cell_j_idx > 0
                x_i = centroid_locations_corrected{session_i}(cell_i_idx, 1);
                y_i = centroid_locations_corrected{session_i}(cell_i_idx, 2);
                x_j = centroid_locations_corrected{session_j}(cell_j_idx, 1);
                y_j = centroid_locations_corrected{session_j}(cell_j_idx, 2);
                
                x_dist = (x_j - x_i) * microns_per_pixel;
                y_dist = (y_j - y_i) * microns_per_pixel;
                euclidean_dist = sqrt(x_dist^2 + y_dist^2);
                
                euclidean_distances(session_i, session_j) = euclidean_dist;
            end
        end
    end
    
    % Set diagonal to 0 only if cell present
    for i = 1:num_sessions
        if optimal_cell_to_index_map(cell_index, i) > 0
            euclidean_distances(i, i) = 0;
        end
    end
    
    % FIXED: Create figure with specified visibility
    fig = figure('Position', [200, 200, 600, 500], 'Visible', figures_visibility);
    
    % Create heatmap with FIXED colorbar range 0-5 microns
    imagesc(euclidean_distances);
    
    set(gca, 'XTick', 1:num_sessions, 'XTickLabel', session_labels);
    set(gca, 'YTick', 1:num_sessions, 'YTickLabel', session_labels);
    xlabel('Session', 'FontSize', 12);
    ylabel('Session', 'FontSize', 12);
    title(sprintf('Cell %d - Distance Between Sessions (μm)', cell_index), 'FontSize', 14, 'FontWeight', 'bold');
    
    colormap(hot);
    c = colorbar;
    c.Label.String = 'Distance (μm)';
    c.Label.FontSize = 12;
    caxis([0 5]); % FIXED COLORBAR RANGE
    
    % Add text annotations
    for i = 1:num_sessions
        for j = 1:num_sessions
            if ~isnan(euclidean_distances(i, j))
                if euclidean_distances(i, j) < 2.5
                    text_color = 'white';
                else
                    text_color = 'black';
                end
                
                text(j, i, sprintf('%.1f', euclidean_distances(i, j)), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', 8, 'Color', text_color, 'FontWeight', 'bold');
            else
                text(j, i, 'N/A', ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', 8, 'Color', 'black', 'FontWeight', 'bold');
            end
        end
    end
    
    axis square;
    
    % Save
    filename = sprintf('cell_%d_distance_heatmap.png', cell_index);
    saveas(fig, fullfile(figures_directory, filename));
    close(fig);
    
    % Print summary
    sessions_present = find(optimal_cell_to_index_map(cell_index, :) > 0);
    actual_sessions_present = session_numbers(sessions_present);
    fprintf('  Cell %d: Present in sessions [%s]\n', cell_index, sprintf('%d ', actual_sessions_present));
    
    valid_mask = ~isnan(euclidean_distances) & euclidean_distances > 0;
    valid_euclidean = euclidean_distances(valid_mask);
    if ~isempty(valid_euclidean)
        fprintf('    Max distance: %.2f μm, Mean: %.2f μm, Min: %.2f μm, Std: %.2f μm\n', ...
                max(valid_euclidean), mean(valid_euclidean), min(valid_euclidean), std(valid_euclidean));
    end
end

function plot_zoomed_cell_comparison(cell_idx, optimal_cell_to_index_map, ...
                                    spatial_footprints_corrected, ...
                                    centroid_locations_corrected, ...
                                    figures_directory, figures_visibility, ...
                                    p_same_registered_pairs, session_numbers, ...
                                    mean_images_enhanced, roi_mappings, ...
                                    microns_per_pixel)
% PLOT_ZOOMED_CELL_COMPARISON - Four-row zoomed comparison with heatmaps and metrics
% MODIFIED: Now shows actual ROI numbers, cell area, IsCellProbability, and heatmaps
%
% Row 1: Zoomed out (full FOV) with small cross at cell location
% Row 2: 3x zoom with thin contour around cell (showing cell area in μm²)
% Row 3: 6x zoom with only center point (showing IsCellProbability)
% Row 4: Distance heatmap (left) and P_same heatmap (right)
    
    num_sessions = size(optimal_cell_to_index_map, 2);

    if nargin < 8
        session_numbers = 1:num_sessions;
    end

    if nargin < 9
        mean_images_enhanced = []; % Will try to load from spatial_footprints
    end

    if nargin < 10
        roi_mappings = []; % Won't show actual ROI numbers
    end

    if nargin < 11
        microns_per_pixel = 1.0; % Default pixel size
        warning('plot_zoomed_cell_comparison:MissingParameter', ...
                'microns_per_pixel parameter not provided. Using default value of 1.0 (assuming 1 pixel = 1 micron). Cell areas may be inaccurate.');
    end

    cell_indices = optimal_cell_to_index_map(cell_idx, :);
    sessions_present = find(cell_indices > 0);
    n_sessions_present = length(sessions_present);
    
    if n_sessions_present == 0
        fprintf('Warning: Cell %d does not appear in any session\n', cell_idx);
        return;
    end
    
    has_p_same = (nargin >= 7) && ~isempty(p_same_registered_pairs) && isnumeric(p_same_registered_pairs);

    % Define zoom levels
    zoom_3x = 50;  % 3x zoom radius (pixels)
    zoom_6x = 25;  % 6x zoom radius (pixels)

    % Calculate figure size (4 rows: FOV, 3x zoom, 6x zoom, heatmaps)
    % Set minimum width for better presentation with 2 sessions
    fig_width = max(800, 250*n_sessions_present);
    fig_height = 1200; % Increased height for 4 rows

    fig_name = sprintf('Cell_%d_Zoomed_Comparison', cell_idx);

    % Create figure with renderer specified for faster saving
    fig = figure('Position', [50, 50, fig_width, fig_height], ...
                 'Name', fig_name, ...
                 'Visible', figures_visibility, ...
                 'Renderer', 'painters'); % painters is faster than opengl for saving
    
    % Get centroids for zoom region
    all_x = [];
    all_y = [];
    for i = 1:n_sessions_present
        sess = sessions_present(i);
        cell_local_idx = cell_indices(sess);
        
        if cell_local_idx > 0 && cell_local_idx <= size(centroid_locations_corrected{sess}, 1)
            x = centroid_locations_corrected{sess}(cell_local_idx, 1);
            y = centroid_locations_corrected{sess}(cell_local_idx, 2);
            all_x = [all_x, x];
            all_y = [all_y, y];
        end
    end
    
    if isempty(all_x) || isempty(all_y)
        fprintf('Warning: Could not get valid centroids for cell %d\n', cell_idx);
        delete(fig); % Use delete instead of close for faster cleanup
        return;
    end
    
    center_x = round(mean(all_x));
    center_y = round(mean(all_y));

    % Calculate subplot grid: 4 rows x n_sessions columns
    total_cols = n_sessions_present;
    total_rows = 4;

    % Store cell areas and probabilities for display
    cell_areas = zeros(1, n_sessions_present);
    cell_probs = zeros(1, n_sessions_present);

    % Plot each session in 3 rows (rows 1-3: FOV, 3x zoom, 6x zoom)
    for i = 1:n_sessions_present
        sess = sessions_present(i);
        actual_session_num = session_numbers(sess);
        cell_local_idx = cell_indices(sess);  % This is the filtered index (1, 2, 3, ...)
        
        % FIXED: Get actual ROI number from database
        actual_roi_number = cell_local_idx; % Default fallback
        cell_prob = NaN; % Default probability
        using_fallback_roi = true; % Flag to track if using fallback

        if ~isempty(roi_mappings) && sess <= length(roi_mappings)
            % cell_local_idx is the filtered index (position in the kept array)
            % We need to find which position in the ORIGINAL array has this filtered_index
            filtered_indices = roi_mappings(sess).filtered_indices;  % e.g., [0, 1, 0, 2, 3, 0]
            original_roi_numbers = roi_mappings(sess).original_roi_numbers;  % e.g., [234, 235, 237, 240, 245, 250]

            % Find the position where filtered_indices == cell_local_idx
            % For example, if cell_local_idx = 2, we want to find position 4 (where filtered_indices(4) = 2)
            original_position = find(filtered_indices == cell_local_idx, 1);

            if ~isempty(original_position)
                % Now get the actual ROI number from that position
                actual_roi_number = original_roi_numbers(original_position);
                using_fallback_roi = false; % Successfully got real ROI number

                % Get IsCellProbability from stored probabilities
                if isfield(roi_mappings(sess), 'probabilities') && ...
                   original_position <= length(roi_mappings(sess).probabilities)
                    cell_prob = roi_mappings(sess).probabilities(original_position);
                end

                fprintf('    Session %d: CellReg filtered index %d → Database ROI #%d (P=%.3f)\n', ...
                        sess, cell_local_idx, actual_roi_number, cell_prob);
            else
                fprintf('    Warning: Session %d, could not find filtered index %d in mapping\n', ...
                        sess, cell_local_idx);
            end
        end

        cell_probs(i) = cell_prob;
        col_idx = i;
        
        try
            % Load footprints
            footprints = load_footprints_data(spatial_footprints_corrected{sess});
            
            % Validate index
            if cell_local_idx <= 0 || (iscell(footprints) && cell_local_idx > length(footprints))
                error('Invalid cell index: %d', cell_local_idx);
            end
            
            % Get cell footprint
            if iscell(footprints)
                cell_footprint = footprints{cell_local_idx};
            elseif isnumeric(footprints) && ndims(footprints) == 3
                cell_footprint = squeeze(footprints(cell_local_idx, :, :));
            else
                cell_footprint = footprints;
            end
            
            if ndims(cell_footprint) > 2
                cell_footprint = squeeze(cell_footprint);
            end
            
            % Get enhanced mean image (for background)
            if ~isempty(mean_images_enhanced) && sess <= length(mean_images_enhanced) && ~isempty(mean_images_enhanced{sess})
                mean_img_enh = mean_images_enhanced{sess};
            else
                % Fallback: use cell footprint
                mean_img_enh = cell_footprint;
            end
            
            % Ensure same size
            if ~isequal(size(mean_img_enh), size(cell_footprint))
                mean_img_enh = imresize(mean_img_enh, size(cell_footprint));
            end
            
            [img_height, img_width] = size(mean_img_enh);
            
            % Get centroid for this session
            if cell_local_idx <= size(centroid_locations_corrected{sess}, 1)
                cent_x = centroid_locations_corrected{sess}(cell_local_idx, 1);
                cent_y = centroid_locations_corrected{sess}(cell_local_idx, 2);
            else
                cent_x = center_x;
                cent_y = center_y;
            end
            
            %% ROW 1: Full FOV with small cross
            subplot(total_rows, total_cols, col_idx);
            
            % Adjust contrast once and reuse
            img_norm = mat2gray(mean_img_enh);
            img_adj = imadjust(img_norm, stretchlim(img_norm, [0.01 0.99]));
            
            imshow(img_adj);
            hold on;
            
            % Draw small cross at cell location (size 10 pixels)
            cross_size = 10;
            plot([cent_x - cross_size, cent_x + cross_size], [cent_y, cent_y], ...
                 'r-', 'LineWidth', 2);
            plot([cent_x, cent_x], [cent_y - cross_size, cent_y + cross_size], ...
                 'r-', 'LineWidth', 2);
            
            % Show actual ROI number from database (with fallback warning if needed)
            if using_fallback_roi
                title(sprintf('S%d - Full FOV (ROI #%d*)\\fontsize{8}\\color{red}*CellReg index', actual_session_num, actual_roi_number), ...
                      'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'tex');
            else
                title(sprintf('S%d - Full FOV (ROI #%d)', actual_session_num, actual_roi_number), ...
                      'FontSize', 10, 'FontWeight', 'bold');
            end
            axis on;
            hold off;
            
            %% ROW 2: 3x zoom with thin contour
            subplot(total_rows, total_cols, col_idx + total_cols);
            
            % Extract 3x zoomed region
            x_min_3x = max(1, round(cent_x - zoom_3x));
            x_max_3x = min(img_width, round(cent_x + zoom_3x));
            y_min_3x = max(1, round(cent_y - zoom_3x));
            y_max_3x = min(img_height, round(cent_y + zoom_3x));
            
            zoomed_3x = mean_img_enh(y_min_3x:y_max_3x, x_min_3x:x_max_3x);
            zoomed_3x_norm = mat2gray(zoomed_3x);
            zoomed_3x_adj = imadjust(zoomed_3x_norm, stretchlim(zoomed_3x_norm, [0.01 0.99]));
            
            imshow(zoomed_3x_adj);
            hold on;
            
            % Calculate cell area from actual ROI pixels (non-zero pixels in footprint)
            area_pixels = sum(cell_footprint(:) > 0);
            area_um2 = area_pixels * (microns_per_pixel^2);
            cell_areas(i) = area_um2;

            % Extract cell footprint region and create thin contour
            cell_region = cell_footprint(y_min_3x:y_max_3x, x_min_3x:x_max_3x);
            binary_mask = cell_region > (0.1 * max(cell_region(:)));

            if any(binary_mask(:))
                boundaries = bwboundaries(binary_mask, 'noholes');
                if ~isempty(boundaries)
                    boundary = boundaries{1};
                    % Draw thin contour (LineWidth 1)
                    plot(boundary(:,2), boundary(:,1), 'r-', 'LineWidth', 1);
                end
            end

            % Show cell area in μm² instead of ROI number
            title(sprintf('S%d - 3x Zoom (Area: %.1f μm²)', actual_session_num, area_um2), ...
                  'FontSize', 10, 'FontWeight', 'bold');
            axis on;
            hold off;
            
            %% ROW 3: 6x zoom with only center point
            subplot(total_rows, total_cols, col_idx + 2*total_cols);
            
            % Extract 6x zoomed region
            x_min_6x = max(1, round(cent_x - zoom_6x));
            x_max_6x = min(img_width, round(cent_x + zoom_6x));
            y_min_6x = max(1, round(cent_y - zoom_6x));
            y_max_6x = min(img_height, round(cent_y + zoom_6x));
            
            zoomed_6x = mean_img_enh(y_min_6x:y_max_6x, x_min_6x:x_max_6x);
            zoomed_6x_norm = mat2gray(zoomed_6x);
            zoomed_6x_adj = imadjust(zoomed_6x_norm, stretchlim(zoomed_6x_norm, [0.01 0.99]));
            
            imshow(zoomed_6x_adj);
            hold on;

            % Draw very small point at center
            local_x = cent_x - x_min_6x + 1;
            local_y = cent_y - y_min_6x + 1;
            plot(local_x, local_y, 'r.', 'MarkerSize', 8);

            % Add IsCellProbability text overlay
            if ~isnan(cell_prob)
                text(0.95, 0.05, sprintf('P(Cell)=%.3f', cell_prob), ...
                     'Units', 'normalized', 'VerticalAlignment', 'bottom', ...
                     'HorizontalAlignment', 'right', 'FontSize', 9, ...
                     'FontWeight', 'bold', 'Color', 'yellow', ...
                     'BackgroundColor', [0 0 0 0.6], ...
                     'EdgeColor', 'yellow', 'LineWidth', 1, 'Margin', 2);
            end

            % Show actual ROI number from database (with fallback warning if needed)
            if using_fallback_roi
                title(sprintf('S%d - 6x Zoom (ROI #%d*)\\fontsize{8}\\color{red}*CellReg index', actual_session_num, actual_roi_number), ...
                      'FontSize', 10, 'FontWeight', 'bold', 'Interpreter', 'tex');
            else
                title(sprintf('S%d - 6x Zoom (ROI #%d)', actual_session_num, actual_roi_number), ...
                      'FontSize', 10, 'FontWeight', 'bold');
            end
            axis on;
            hold off;
            
        catch ME
            fprintf('  Warning: Could not process session %d for cell %d: %s\n', ...
                    actual_session_num, cell_idx, ME.message);

            % Show error in first three rows
            for row = 1:3
                subplot(total_rows, total_cols, col_idx + (row-1)*total_cols);
                text(0.5, 0.5, sprintf('Error\nSession %d', actual_session_num), ...
                     'HorizontalAlignment', 'center', 'Color', 'r', ...
                     'FontSize', 10, 'FontWeight', 'bold');
                axis off;
            end
        end
    end
    
    %% ROW 4: Distance and P_same Heatmaps side by side
    % Calculate distance matrix between sessions
    euclidean_distances = NaN(n_sessions_present, n_sessions_present);

    for i = 1:n_sessions_present
        for j = 1:n_sessions_present
            sess_i = sessions_present(i);
            sess_j = sessions_present(j);
            cell_i_idx = cell_indices(sess_i);
            cell_j_idx = cell_indices(sess_j);

            if cell_i_idx > 0 && cell_j_idx > 0
                x_i = centroid_locations_corrected{sess_i}(cell_i_idx, 1);
                y_i = centroid_locations_corrected{sess_i}(cell_i_idx, 2);
                x_j = centroid_locations_corrected{sess_j}(cell_j_idx, 1);
                y_j = centroid_locations_corrected{sess_j}(cell_j_idx, 2);

                x_dist = (x_j - x_i) * microns_per_pixel;
                y_dist = (y_j - y_i) * microns_per_pixel;
                euclidean_distances(i, j) = sqrt(x_dist^2 + y_dist^2);
            end
        end
    end

    % Determine subplot layout for row 4
    % Create two heatmaps side by side using subplot positioning
    session_labels = cell(1, n_sessions_present);
    for i = 1:n_sessions_present
        session_labels{i} = sprintf('S%d', session_numbers(sessions_present(i)));
    end

    % Calculate positions for the two heatmaps in row 4
    % Row 4 should span the full width, split into left (distance) and right (p_same)
    row_4_bottom = 0.05;  % Bottom position for row 4
    row_4_height = 0.20;  % Height of row 4
    gap = 0.05;           % Gap between heatmaps
    margin = 0.05;        % Left/right margins

    % Distance Heatmap (left side of row 4)
    left_width = (1 - 2*margin - gap) / 2;
    pos_left = [margin, row_4_bottom, left_width, row_4_height];

    ax_dist = subplot('Position', pos_left);

    imagesc(euclidean_distances);
    set(gca, 'XTick', 1:n_sessions_present, 'XTickLabel', session_labels);
    set(gca, 'YTick', 1:n_sessions_present, 'YTickLabel', session_labels);
    xlabel('Session', 'FontSize', 10, 'FontWeight', 'bold');
    ylabel('Session', 'FontSize', 10, 'FontWeight', 'bold');
    title('Distance Between Sessions (μm)', 'FontSize', 11, 'FontWeight', 'bold');

    colormap(gca, hot);
    c = colorbar;
    c.Label.String = 'Distance (μm)';
    c.Label.FontSize = 10;
    caxis([0 5]); % Fixed colorbar range 0-5 μm

    % Add text annotations
    for i = 1:n_sessions_present
        for j = 1:n_sessions_present
            if ~isnan(euclidean_distances(i, j))
                if euclidean_distances(i, j) < 2.5
                    text_color = 'white';
                else
                    text_color = 'black';
                end
                text(j, i, sprintf('%.1f', euclidean_distances(i, j)), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', 8, 'Color', text_color, 'FontWeight', 'bold');
            else
                text(j, i, 'N/A', ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                     'FontSize', 7, 'Color', 'black');
            end
        end
    end

    axis square;

    % P_same Heatmap (right side of row 4)
    if has_p_same
        try
            p_same_matrix = extract_p_same_for_cell(cell_idx, optimal_cell_to_index_map, ...
                                                    p_same_registered_pairs, sessions_present);

            % Right heatmap position
            pos_right = [margin + left_width + gap, row_4_bottom, left_width, row_4_height];
            ax_psame = subplot('Position', pos_right);

            imagesc(p_same_matrix);
            set(gca, 'XTick', 1:n_sessions_present, 'XTickLabel', session_labels);
            set(gca, 'YTick', 1:n_sessions_present, 'YTickLabel', session_labels);
            xlabel('Session', 'FontSize', 10, 'FontWeight', 'bold');
            ylabel('Session', 'FontSize', 10, 'FontWeight', 'bold');
            title('P(Same Cell)', 'FontSize', 11, 'FontWeight', 'bold');

            colormap(gca, jet);
            c = colorbar;
            c.Label.String = 'Probability';
            c.Label.FontSize = 10;
            caxis([0 1]);

            % Add text annotations
            for i = 1:n_sessions_present
                for j = 1:n_sessions_present
                    if ~isnan(p_same_matrix(i, j))
                        if p_same_matrix(i, j) > 0.5
                            text_color = 'white';
                        else
                            text_color = 'black';
                        end
                        text(j, i, sprintf('%.2f', p_same_matrix(i, j)), ...
                             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                             'FontSize', 8, 'Color', text_color, 'FontWeight', 'bold');
                    else
                        text(j, i, 'N/A', ...
                             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                             'FontSize', 7, 'Color', 'black');
                    end
                end
            end

            axis square;
        catch ME
            fprintf('  Warning: Could not create P_same heatmap: %s\n', ME.message);
        end
    end
    
    % Add overall title
    actual_sessions_str = sprintf('%d ', session_numbers(sessions_present));
    sgtitle(sprintf('Cell %d - 4-Level Analysis: FOV, 3x Zoom, 6x Zoom, Heatmaps (Sessions: %s)', cell_idx, actual_sessions_str), ...
            'FontSize', 13, 'FontWeight', 'bold');
    
    % OPTIMIZED SAVING - The key to preventing hangs
    filename_png = fullfile(figures_directory, sprintf('Cell_%d_zoomed_comparison.png', cell_idx));
    filename_fig = fullfile(figures_directory, sprintf('Cell_%d_zoomed_comparison.fig', cell_idx));
    
    try
        % Force all rendering to complete before saving
        drawnow limitrate nocallbacks;
        
        % Save PNG using print (much faster and more reliable than saveas)
        print(fig, filename_png, '-dpng', '-r150');
        
        % Save FIG format (useful for reopening in MATLAB)
        % Use hgsave which is more robust than saveas
        hgsave(fig, filename_fig);
        
    catch ME
        warning('Error saving cell %d: %s. Attempting fallback save...', cell_idx, ME.message);
        
        % Fallback: try different save method
        try
            exportgraphics(fig, filename_png, 'Resolution', 150);
        catch
            fprintf('  Could not save PNG for cell %d\n', cell_idx);
        end
        
        try
            savefig(fig, filename_fig);
        catch
            fprintf('  Could not save FIG for cell %d\n', cell_idx);
        end
    end
    
    % Always delete figure immediately to free memory (faster than close)
    delete(fig);

    fprintf('  Created 4-level analysis figure for cell %d (sessions: %s)\n', ...
            cell_idx, sprintf('%d ', session_numbers(sessions_present)));
end

function footprints = load_footprints_data(footprint_file)
% LOAD_FOOTPRINTS_DATA - ROBUST version handles all formats

    try
        if ischar(footprint_file) || isstring(footprint_file)
            data = load(footprint_file);
            if isfield(data, 'footprint')
                footprints = data.footprint;
            elseif isfield(data, 'footprints')
                footprints = data.footprints;
            else
                error('Could not find footprint data in file');
            end
            
        elseif iscell(footprint_file)
            footprints = footprint_file;
            
        elseif isnumeric(footprint_file)
            if ndims(footprint_file) == 3
                n_cells = size(footprint_file, 1);
                footprints = cell(1, n_cells);
                for i = 1:n_cells
                    footprints{i} = squeeze(footprint_file(i, :, :));
                end
            elseif ndims(footprint_file) == 2
                footprints = {footprint_file};
            else
                error('Unexpected numeric array dimensions: %d', ndims(footprint_file));
            end
            
        else
            error('Unexpected footprint data type: %s', class(footprint_file));
        end
        
        % Convert sparse to full and ensure 2D
        if iscell(footprints)
            for i = 1:length(footprints)
                if issparse(footprints{i})
                    footprints{i} = full(footprints{i});
                end
                if ndims(footprints{i}) > 2
                    footprints{i} = squeeze(footprints{i});
                end
            end
        end
        
    catch ME
        error('Failed to load footprints: %s\nData type: %s', ME.message, class(footprint_file));
    end
end

function p_same_matrix = extract_p_same_for_cell(cell_idx, optimal_cell_to_index_map, ...
                                                 p_same_registered_pairs, sessions_present)
% EXTRACT_P_SAME_FOR_CELL - Extract P_same values for specific cell

    n_sessions_present = length(sessions_present);
    p_same_matrix = NaN(n_sessions_present, n_sessions_present);

    for i = 1:n_sessions_present
        p_same_matrix(i, i) = 1;
    end

    % Check if cell_idx is within bounds of p_same_registered_pairs
    if isempty(p_same_registered_pairs) || cell_idx > size(p_same_registered_pairs, 1)
        warning('Cell %d is out of bounds for p_same_registered_pairs (size: %d x %d)', ...
                cell_idx, size(p_same_registered_pairs, 1), size(p_same_registered_pairs, 2));
        return;
    end

    num_sessions_total = size(optimal_cell_to_index_map, 2);

    pair_idx = 0;
    for sess_i = 1:num_sessions_total-1
        for sess_j = sess_i+1:num_sessions_total
            pair_idx = pair_idx + 1;

            idx_i = find(sessions_present == sess_i, 1);
            idx_j = find(sessions_present == sess_j, 1);

            if ~isempty(idx_i) && ~isempty(idx_j)
                if pair_idx <= size(p_same_registered_pairs, 2)
                    p_val = p_same_registered_pairs(cell_idx, pair_idx);

                    if ~isnan(p_val) && p_val >= 0
                        p_same_matrix(idx_i, idx_j) = p_val;
                        p_same_matrix(idx_j, idx_i) = p_val;
                    end
                end
            end
        end
    end
end

function plot_session_venn_diagram(optimal_cell_to_index_map, figures_directory, ...
                                   figures_visibility, session_numbers, subject_id, nonzero_counts)
% PLOT_SESSION_VENN_DIAGRAM - Venn diagram with histogram showing cell occurrences

    num_sessions = size(optimal_cell_to_index_map, 2);

    if nargin < 4
        session_numbers = 1:num_sessions;
    end

    if nargin < 5
        subject_id = [];  % Default to no subject ID
    end

    if nargin < 6
        % Calculate nonzero_counts if not provided
        nonzero_counts = sum(optimal_cell_to_index_map > 0, 2);
    end

    % Create binary presence matrix (1 if cell present, 0 if not)
    presence_matrix = optimal_cell_to_index_map > 0;

    % Create figure with space for Venn/UpSet diagram and histogram
    fig = figure('Position', [200, 200, 1000, 900], 'Visible', figures_visibility);

    % Create two subplot rows with position-based layout to avoid overlap
    if num_sessions >= 4
        % For UpSet plots (4+ sessions), give more space to top plot
        pos_top = [0.10, 0.38, 0.85, 0.57];  % [left, bottom, width, height]
        pos_bottom = [0.10, 0.05, 0.85, 0.25];
    else
        % For Venn diagrams (2-3 sessions), standard spacing
        pos_top = [0.10, 0.35, 0.85, 0.60];
        pos_bottom = [0.10, 0.05, 0.85, 0.25];
    end

    % Top subplot for Venn/UpSet diagram
    subplot('Position', pos_top);

    if num_sessions == 2
        % Two-circle Venn diagram
        plot_2_way_venn(presence_matrix, session_numbers);

    elseif num_sessions == 3
        % Three-circle Venn diagram
        plot_3_way_venn(presence_matrix, session_numbers);

    else
        % For 4+ sessions, use UpSet plot style (better than Venn)
        plot_upset_style(presence_matrix, session_numbers);
    end

    % Bottom subplot for histogram
    subplot('Position', pos_bottom);
    histogram(nonzero_counts, 'BinMethod', 'integers', 'FaceColor', [0.3 0.5 0.8], 'EdgeColor', 'k');
    xlabel('Number of Sessions', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Number of Cells', 'FontSize', 12, 'FontWeight', 'bold');
    title('Distribution of Cell Occurrences Across Sessions', 'FontSize', 13, 'FontWeight', 'bold');
    grid on;

    % Add statistics text
    hold on;
    max_val = max(nonzero_counts);
    ylims = ylim;
    text(0.7*max_val, 0.85*ylims(2), sprintf('Total cells: %d\nCells in all sessions: %d\nCells in ≥2 sessions: %d', ...
         length(nonzero_counts), sum(nonzero_counts == num_sessions), sum(nonzero_counts >= 2)), ...
         'FontSize', 10, 'FontWeight', 'bold', 'BackgroundColor', 'white', 'EdgeColor', 'black');
    hold off;

    % Add title with subject ID
    if ~isempty(subject_id)
        sgtitle(sprintf('Subject %d - Cell Overlap Between Sessions', subject_id), ...
                'FontSize', 16, 'FontWeight', 'bold');
    else
        sgtitle(sprintf('Cell Overlap Between Sessions'), ...
                'FontSize', 16, 'FontWeight', 'bold');
    end
    
    % FIXED: Force rendering to complete before saving
    drawnow;
    
    % FIXED: Use more robust saving methods
    png_filename = fullfile(figures_directory, 'Session_Venn_Diagram.png');
    fig_filename = fullfile(figures_directory, 'Session_Venn_Diagram.fig');
    
    try
        % Save PNG using print (more reliable)
        print(fig, png_filename, '-dpng', '-r300');
        fprintf('  Saved Venn diagram PNG: %s\n', png_filename);
    catch ME
        fprintf('  Warning: Could not save Venn PNG: %s\n', ME.message);
        try
            % Fallback to saveas
            saveas(fig, png_filename);
        catch
            fprintf('  Error: Failed to save PNG completely\n');
        end
    end
    
    try
        % Save FIG format
        savefig(fig, fig_filename);
        fprintf('  Saved Venn diagram FIG: %s\n', fig_filename);
    catch ME
        fprintf('  Warning: Could not save Venn FIG: %s\n', ME.message);
    end
    
    % Close if visibility was off
    if strcmp(figures_visibility, 'off')
        close(fig);
    end
end

function plot_2_way_venn(presence_matrix, session_numbers)
    % 2-way Venn diagram with correct counts
    
    % Calculate all regions
    only_sess1 = sum(presence_matrix(:, 1) & ~presence_matrix(:, 2));
    only_sess2 = sum(~presence_matrix(:, 1) & presence_matrix(:, 2));
    both = sum(presence_matrix(:, 1) & presence_matrix(:, 2));
    
    % Draw circles
    theta = linspace(0, 2*pi, 100);
    r = 1;
    
    % Circle for Session 1 (left)
    x_sess1 = r * cos(theta) - 0.5;
    y_sess1 = r * sin(theta);
    
    % Circle for Session 2 (right)
    x_sess2 = r * cos(theta) + 0.5;
    y_sess2 = r * sin(theta);
    
    hold on;
    fill(x_sess1, y_sess1, [0.7 0.7 1], 'FaceAlpha', 0.3, 'EdgeColor', 'b', 'LineWidth', 2);
    fill(x_sess2, y_sess2, [1 0.7 0.7], 'FaceAlpha', 0.3, 'EdgeColor', 'r', 'LineWidth', 2);
    
    % Add count labels - adjusted positions
    text(-1.1, 0, sprintf('%d', only_sess1), 'FontSize', 20, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(1.1, 0, sprintf('%d', only_sess2), 'FontSize', 20, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    text(0, 0, sprintf('%d', both), 'FontSize', 20, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % Session labels
    text(-1, 1.5, sprintf('Session %d', session_numbers(1)), 'FontSize', 14, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center', 'Color', 'b');
    text(1, 1.5, sprintf('Session %d', session_numbers(2)), 'FontSize', 14, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center', 'Color', 'r');
    
    % Add summary text
    total_sess1 = only_sess1 + both;
    total_sess2 = only_sess2 + both;
    text(0, -1.7, sprintf('Total S%d: %d | Total S%d: %d | Intersection: %d', ...
         session_numbers(1), total_sess1, session_numbers(2), total_sess2, both), ...
         'FontSize', 12, 'HorizontalAlignment', 'center');
    
    axis equal;
    axis off;
    xlim([-2.5 2.5]);
    ylim([-2.2 2]);
    hold off;
end

function plot_3_way_venn(presence_matrix, session_numbers)
    % 3-way Venn diagram with ALL 7 regions correctly calculated
    
    % Calculate all 7 regions (excluding "none")
    sess1 = presence_matrix(:, 1);
    sess2 = presence_matrix(:, 2);
    sess3 = presence_matrix(:, 3);
    
    only_sess1 = sum(sess1 & ~sess2 & ~sess3);           % Only in Session 1
    only_sess2 = sum(~sess1 & sess2 & ~sess3);           % Only in Session 2
    only_sess3 = sum(~sess1 & ~sess2 & sess3);           % Only in Session 3
    sess1_and_sess2 = sum(sess1 & sess2 & ~sess3);       % S1 ∩ S2 only (not S3)
    sess1_and_sess3 = sum(sess1 & ~sess2 & sess3);       % S1 ∩ S3 only (not S2)
    sess2_and_sess3 = sum(~sess1 & sess2 & sess3);       % S2 ∩ S3 only (not S1)
    all_three = sum(sess1 & sess2 & sess3);              % S1 ∩ S2 ∩ S3
    
    theta = linspace(0, 2*pi, 100);
    r = 1;
    
    % Three circles positioned in triangle
    angles = [90, 210, 330] * pi/180;
    colors = [0.7 0.7 1; 1 0.7 0.7; 0.7 1 0.7];
    
    hold on;
    for i = 1:3
        x_c = 0.6 * cos(angles(i));
        y_c = 0.6 * sin(angles(i));
        
        x = r * cos(theta) + x_c;
        y = r * sin(theta) + y_c;
        
        fill(x, y, colors(i,:), 'FaceAlpha', 0.2, 'EdgeColor', colors(i,:)*0.5, 'LineWidth', 2);
    end
    
    % Position labels for all 7 regions - ADJUSTED POSITIONS (moved further out)
    % Only Session 1 (top) - moved further up
    text(0.6*cos(angles(1))*1.8, 0.6*sin(angles(1))*1.8, sprintf('%d', only_sess1), ...
         'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % Only Session 2 (bottom left) - moved further left/down
    text(0.6*cos(angles(2))*1.8, 0.6*sin(angles(2))*1.8, sprintf('%d', only_sess2), ...
         'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % Only Session 3 (bottom right) - moved further right/down
    text(0.6*cos(angles(3))*1.8, 0.6*sin(angles(3))*1.8, sprintf('%d', only_sess3), ...
         'FontSize', 16, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % S1 ∩ S2 (between Session 1 and 2, left side) - moved away from center
    text(0.45*cos(angles(1)) + 0.45*cos(angles(2)), ...
         0.45*sin(angles(1)) + 0.45*sin(angles(2)), ...
         sprintf('%d', sess1_and_sess2), 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % S1 ∩ S3 (between Session 1 and 3, right side) - moved away from center
    text(0.45*cos(angles(1)) + 0.45*cos(angles(3)), ...
         0.45*sin(angles(1)) + 0.45*sin(angles(3)), ...
         sprintf('%d', sess1_and_sess3), 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % S2 ∩ S3 (between Session 2 and 3, bottom) - moved away from center
    text(0.45*cos(angles(2)) + 0.45*cos(angles(3)), ...
         0.45*sin(angles(2)) + 0.45*sin(angles(3)), ...
         sprintf('%d', sess2_and_sess3), 'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    % All three (center) - kept at center
    text(0, 0, sprintf('%d', all_three), 'FontSize', 16, 'FontWeight', 'bold', ...
         'HorizontalAlignment', 'center', 'BackgroundColor', 'white', 'EdgeColor', 'black');
    
    % Session labels - moved further out
    for i = 1:3
        text(2.2*cos(angles(i)), 2.2*sin(angles(i)), sprintf('Session %d', session_numbers(i)), ...
             'FontSize', 14, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end
    
    % Add summary text with session numbers
    total_sess1 = only_sess1 + sess1_and_sess2 + sess1_and_sess3 + all_three;
    total_sess2 = only_sess2 + sess1_and_sess2 + sess2_and_sess3 + all_three;
    total_sess3 = only_sess3 + sess1_and_sess3 + sess2_and_sess3 + all_three;
    
    text(0, -2.5, sprintf('Total: S%d=%d | S%d=%d | S%d=%d | All 3=%d', ...
         session_numbers(1), total_sess1, session_numbers(2), total_sess2, ...
         session_numbers(3), total_sess3, all_three), ...
         'FontSize', 11, 'HorizontalAlignment', 'center');
    
    axis equal;
    axis off;
    xlim([-2.8 2.8]);
    ylim([-2.8 2.8]);
    hold off;
end

function plot_upset_style(presence_matrix, session_numbers)
    % UpSet plot style for 4+ sessions (better than Venn for many sets)
    
    % Count all combinations
    [unique_combos, ~, ic] = unique(presence_matrix, 'rows');
    combo_counts = accumarray(ic, 1);
    
    % Sort by count
    [sorted_counts, sort_idx] = sort(combo_counts, 'descend');
    sorted_combos = unique_combos(sort_idx, :);
    
    % Plot top 20 combinations
    n_show = min(20, length(sorted_counts));
    
    subplot(2, 1, 1);
    bar(sorted_counts(1:n_show));
    ylabel('Number of Cells', 'FontSize', 12, 'FontWeight', 'bold');
    title('Top Cell Combinations Across Sessions', 'FontSize', 14);
    grid on;
    
    % Add value labels on bars
    for i = 1:n_show
        text(i, sorted_counts(i), sprintf('%d', sorted_counts(i)), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
             'FontSize', 9, 'FontWeight', 'bold');
    end
    
    subplot(2, 1, 2);
    imagesc(sorted_combos(1:n_show, :)');
    colormap([1 1 1; 0.2 0.4 0.8]);
    
    session_labels = arrayfun(@(x) sprintf('S%d', x), session_numbers, 'UniformOutput', false);
    set(gca, 'YTick', 1:length(session_numbers), 'YTickLabel', session_labels);
    set(gca, 'XTick', 1:n_show);
    xlabel('Combination Rank', 'FontSize', 12, 'FontWeight', 'bold');
    ylabel('Sessions', 'FontSize', 12, 'FontWeight', 'bold');
    title('Session Presence Pattern', 'FontSize', 14);
    
    % Add grid
    hold on;
    for i = 0.5:1:length(session_numbers)+0.5
        plot([0.5 n_show+0.5], [i i], 'k-', 'LineWidth', 0.5);
    end
    for i = 0.5:1:n_show+0.5
        plot([i i], [0.5 length(session_numbers)+0.5], 'k-', 'LineWidth', 0.5);
    end
    hold off;
    
    % Add summary statistics
    num_sessions = size(presence_matrix, 2);
    cells_in_all = sum(all(presence_matrix, 2));
    cells_in_any = sum(any(presence_matrix, 2));
    
    % Calculate pairwise intersections
    fprintf('\n  Pairwise Intersections:\n');
    for i = 1:num_sessions-1
        for j = i+1:num_sessions
            intersection = sum(presence_matrix(:,i) & presence_matrix(:,j));
            fprintf('    Sessions %d & %d: %d cells\n', ...
                    session_numbers(i), session_numbers(j), intersection);
        end
    end
    
    fprintf('  Cells in all sessions: %d\n', cells_in_all);
    fprintf('  Cells in at least one session: %d\n', cells_in_any);
end

function bin_rep = de2bi(dec_num, n_bits)
    % Convert decimal to binary array
    bin_rep = zeros(1, n_bits);
    for i = 1:n_bits
        bin_rep(i) = mod(dec_num, 2);
        dec_num = floor(dec_num / 2);
    end
end