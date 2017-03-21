%% Roi-based MVPA for single subject (run_split_half_correlations_single_sub)
%
% Load beta image data from one subject, apply 'vt' mask, compute difference
% of (fisher-transformed) between on- and off diagonal split-half
% correlation values.
%
% #   For CoSMoMVPA's copyright information and license terms,   #
% #   see the COPYING file distributed with CoSMoMVPA.           #

if isunix % if we are Hammer, a unix system
    addpath(genpath('/gpfs/group/n/nad12/RSA/Scripts/CoSMoMVPA-master'))
else % if not on unix, assume we are on Anvil
    addpath(genpath('S:\nad12\CoSMoMVPA-master'))
end

%% Set analysis parameters
subjects   = {'18y404'  '18y566'  '20y297' '20y415'  '20y439'}; % '20y396'
rois       = {'rLTG_left'}; %add in leftHC and right HC for starters
study_path = '/gpfs/group/n/nad12/RSA/Analysis_ret/FAMEret8RSA_hrf';

% initalizing the sum of weighted zs all array
z_all   = cell(1,length(rois));
rho_all = cell(1,length(rois));

for ss = 1:length(subjects)
 
    % Edit the SPM.mat file to use paths here on Hammer
    if isunix
        spm_changepath(fullfile(study_path, subjects{ss}, 'SPM.mat'), 'S:\nad12\FAME8', '/gpfs/group/n/nad12/RSA')
        spm_changepath(fullfile(study_path, subjects{ss}, 'SPM.mat'), '\', '/')
    end
    
    %% Computations
    data_path  = fullfile(study_path, subjects{ss});
    
    % Average Betas
    average_betas(subjects{ss}, study_path, 'HREC', '.*HREC.*');
    average_betas(subjects{ss}, study_path, 'HFAM', '.*HFAM.*');
    average_betas(subjects{ss}, study_path, 'FAREC', '.*FAREC.*');
    average_betas(subjects{ss}, study_path, 'FAFAM', '.*FAFAM.*');
    
  for rr = 1:length(rois)

    roi_label = rois{rr}; % name of ROI mask used for running correlations  

    % the averaged betas
    HREC     = fullfile(data_path, 'average_beta_HREC.nii');
    HFAM     = fullfile(data_path, 'average_beta_HFAM.nii');
    FAREC    = fullfile(data_path, 'average_beta_FAREC.nii');
    FAFAM    = fullfile(data_path, 'average_beta_FAFAM.nii');
    
    mask_fn  = fullfile(study_path, [roi_label '.nii']); %second half of mask name

    % load two halves as CoSMoMVPA dataset structs.
    % Chunks = Runs  Targets = trial type conditions
    HREC_ds  = cosmo_fmri_dataset(HREC,'mask',mask_fn,... %encoding... run 1 (chunk) Target(rem) will be identified as 1
                                         'targets',(1)',... %ex: Rem
                                         'chunks',(1)); %ex: encoding (avg. of all enc runs)

    HFAM_ds  = cosmo_fmri_dataset(HFAM,'mask',mask_fn,...
                                         'targets',(2)',... %ex. Know
                                         'chunks',(1)); %encoding (avg. of all enc runs)

    FAREC_ds = cosmo_fmri_dataset(FAREC,'mask',mask_fn,...
                                         'targets',(3)',... %New
                                         'chunks',(1)); %ret
                                     
    FAFAM_ds = cosmo_fmri_dataset(FAFAM,'mask',mask_fn,...
                                         'targets',(4)',... %New
                                         'chunks',(1)); %ret
   
    % Combine files at encoding and retrieval to create two files (i.e.,
    % stacking)
    % make sure all ds_* changed from here on
    ds_all   = cosmo_stack({HREC_ds, HFAM_ds, FAREC_ds, FAFAM_ds});

    % Data set labels
    ds_all.sa.labels = {'HREC';'HFAM';'FAREC';'FAFAM'}; 
    
    % cosmo fxn to make sure data in right format
    cosmo_check_dataset(ds_all);

    % change if you change ds_* above
    nClasses = numel(ds_all.sa.labels);

    % get the sample data - samples are the correlations being ran on each
    % voxel (a bunch of numbers)
    all_ds_samples = ds_all.samples;

    % compute all correlation values between the two halves, resulting
    % in a 6x6 matrix. Store this matrix in a variable 'rho'.
    % Hint: use cosmo_corr (or builtin corr, if the matlab stats toolbox
    %       is available) after transposing the samples in the two halves.
    % >@@>
    rho = cosmo_corr(all_ds_samples');
    % <@@<

    % Correlations are limited between -1 and +1, thus they cannot be normally
    % distributed. To make these correlations more 'normal', apply a Fisher
    % transformation and store this in a variable 'z'
    % (hint: use atanh).
    % >@@>
    z = atanh(rho);
    % <@@<

    %% store and save results
    output_path = fullfile(study_path, subjects{ss}, 'RSA_Results');

    if ~exist(output_path, 'dir')
        mkdir(output_path)
    end
    
    %% Write r matrix to Excel
    filename = ['RSAtest_', subjects{ss}, '_' roi_label '_rho_.xlsx'];
    rho %#ok<*NOPTS>
    xlswrite(fullfile(output_path, filename), rho)

    %% Write z matrix to Excel
    filename = ['RSAtest_', subjects{ss}, '_' roi_label '_z_.xlsx'];
    z
    xlswrite(fullfile(output_path, filename), z)

    %% Store result in a structure for later calculations

    % store the result for this subject in z_all
    % (at the i_subj-th position), so that
    % group statistics can be computed
    % >@@>
    z_all{rr}   = cat(3, z_all{rr}, z);
    rho_all{rr} = cat(3, rho_all{rr}, rho);
    % <@@<
    
    
  end

end

%% Compute T-Statistics

stats_all = cell(1,length(rois));

for rr = 1:length(rois)
    
    [rows, cols, ~] = size(z_all{rr});
    
    for crow = 1:rows
        for ccol = 1:cols
            [h,p,ci,stats]            = ttest(z_all{rr}(crow,ccol,:));
            stats_all{rr}(crow, ccol) = stats.tstat;
        end
    end
    
    fprintf('T Statistics = \n\n')
    disp(stats_all{rr})
    
end

%% Display Averaged Rho Matrices

% plot an image of the correlation matrix averaged over
% participants (one for each roi)

% allocate space for axis handles, so that later all plots can be set to
% have the same color limits
ax_handles = zeros(length(rois),1);
col_limits = zeros(length(rois),2);

for rr = 1:length(rois)
    figure

    % store axis handle for current figure
    ax_handles(rr) = gca;

    % compute the average correlation matrix using 'rho_sum', and store the
    % result in a variable 'rho_mean'. Note that the number of subjects is
    % stored in a variable 'nsubjects'
    % >@@>
    [~,~,nsubjs] = size(rho_all{rr});
    rho_mean     = sum(rho_all{rr}, 3)/nsubjs;
    % <@@<

    % visualize the rho_mean matrix using imagesc
    % >@@>
    imagesc(rho_mean);
    % <@@<

    % set labels, colorbar and title
    set(gca, 'xtick', 1:numel(ds_all.sa.labels), 'xticklabel', ds_all.sa.labels)
    set(gca, 'ytick', 1:numel(ds_all.sa.labels), 'yticklabel', ds_all.sa.labels)

    colorbar
    desc=sprintf(['Average splithalf correlation across subjects '...
                    'in mask ''%s'''], rois{rr});
    title(desc)


    col_limits(rr,:) = get(gca, 'clim');
end

% give all figures the same color limits such that correlations can be
% compared visually
set(ax_handles, 'clim', [min(col_limits(:)), max(col_limits(:))])