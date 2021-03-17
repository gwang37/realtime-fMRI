
clearvars; close all;

pause('on');
% workingdir='/Users/harissair/Desktop/realtime_test_data/real_time';
% addpath('/Users/harissair/Desktop/realtime_test_data/scripts');

workingdir = "."; % data folder 
maskdir = "../SPM8_apriori/"; % mask folder

addpath ./code; % code folder
cd(workingdir);

I_pre = 30; % Time Needed for preprocessing
window_width = 50; % sliding window width
tr=2; %TR
% seedval=[];
ROI_size=3; % ROI neighborhood size
brainMask_Threshold = 0.005;
bp_filt = [.01, 10]; % bandpass filtering 
NmotionPars = 6; % number of motion parameters
nica = 15; % number of ICA component
NT = 1e3; % length scanning

% Other initalization parameters
size3d = [64, 64, 36];
tform_old = affine3d(eye(4));
imINIT = zeros(size3d);
smooth_sig = 3/2.3556;
vol_pre=rand(64,64,36,I_pre-1,'single');
sm_vol_4d = zeros(64, 64, 36, I_pre-1);
ica_ind = 1;
nICAconc = 20;
motion_tol = 1e-7;
frmIdx = 1;
icasig0 = nan;
TissueApriori = loadMask(maskdir);
ATinv = [];
volVec = zeros(64*64*36, NT);
smoothedvolume=zeros(64*64*36, NT);
nuisX_comb = zeros(NT, 26);
ROIval1 = [];
volRaw =zeros(64*64*36, NT);

answer = {'48','26','25','48','43','25'}'; % predefined seeds location.

[f1, f2, f3, sAXs, fill_s, line_s, f2subplots, f3subplots] = CreateFigures(imINIT);

inds = 2:300;
for i = 1: length(inds)
    tic
    [X,dcmfile] = loadDICOM(i, tr, inds);
    if i==1
        % LOAD THE FIRST IMAGE AND INITIALIZE THE STORAGE
        [volumeoriginal,brainmask,brainmaskNaN, icaSigConc, maskIDXs, volVec, volRaw, smoothedvolume] = ...
            initializeStorage(X,nica, nICAconc, brainMask_Threshold, NT);
        
        % Create the Slice_Indices for the Slice Time Correction
        [slice_times, slice_indices] = sliceTimeInfo(dcmfile, maskIDXs);
        
        %open a dialog to choose seeds
        if isempty(answer), answer = chooseSeed(X); end
        uif = uifigure;
        d = uiprogressdlg(uif,'Title','Processing Preliminary Scans','Indeterminate','on');
        pause(0.1);
        
        % CREATE NEIGHBORHOOD INDEX
        [nbhd_idxs, nbhd1_ind, nbhd2_ind] = find_nbhd_inds(answer, brainmaskNaN, maskIDXs, ROI_size);
        
        % CREATE THE WM AND CSF MASK
        [wm_csf_mask] = CreateWMandCSFmask(TissueApriori,brainmask);
        
    elseif i <= I_pre
        % preliminary preprocessing
        [nuisX_comb, tform_old, volVec, volRaw] =...
            prel_preprocessing(i, X, maskIDXs, volRaw, slice_times, slice_indices, tr,...
            brainmask, tform_old, volVec, nuisX_comb, volumeoriginal, wm_csf_mask, motion_tol);
        
    else
        close(d);
        
        set(f1,'visible','on');
        set(f2,'visible','on');
        set(f3,'visible','on');
        % preprocessing
        [VOL_proc, volRaw, tform_old, volVec, smoothedvolume, nuisX_comb, ATinv] =...
            preprocessing(i, I_pre, nuisX_comb, volVec, brainmask, smooth_sig, maskIDXs, smoothedvolume,X, volRaw, ...
            slice_times,  slice_indices, tr,volumeoriginal, wm_csf_mask, motion_tol, tform_old, bp_filt, ATinv);
        
        % update Mval, etc
        [sm_vol, Mval,norMval, norMvaldetrend] = MValupdates(VOL_proc, nbhd1_ind, nbhd2_ind);
        
        if rem(i , 1)==0
            % time series correlations
            [LeftX, RightX] = updateplot_timeSeries(sAXs, fill_s, line_s, window_width, Mval, norMval, norMvaldetrend);
            
            % update correlation plot
            b = norMval(LeftX: RightX,1) - mean(norMval(LeftX: RightX,1));
            corr_vol = corr(sm_vol(:,LeftX: RightX)', norMval(LeftX: RightX,1) , 'rows', 'complete');
            Corrmap = brainmaskNaN; Corrmap(maskIDXs) = corr_vol;
            
            % correlation maps with first seed - c
            sgtitle(f2, "Correlation Maps - Scan " + i);
            for fig = 1:12,  set(f2subplots{fig, 1}, 'CData', Corrmap(:,:,fig*2+7));end; drawnow;
            frame_corrmap(frmIdx) = getframe(f2);
            frmIdx = frmIdx+1;
            
            % update ICA
            [icasig0,icaSigConc,ica_ind, ncomp] = ...
                icaUpdates(sm_vol, icasig0, ica_ind, icaSigConc, LeftX, RightX, b, nbhd_idxs, nICAconc);
            
            icacomp = brainmaskNaN;
            for fig = 1:min(12, ncomp)
                icacomp(maskIDXs) = icasig0(fig, :);
                set(f3subplots{fig, 1}, 'CData', icacomp(:,:,25));
            end
            drawnow
        end
    end
    %
    toc
end

writerObj = VideoWriter('demo.avi');
writerObj.FrameRate = 1;
open(writerObj);
for i=1:length(frame_corrmap)
    % convert the image to a frame
    frame = frame_corrmap(i) ;
    writeVideo(writerObj, frame);
end
% close the writer object
close(writerObj);
