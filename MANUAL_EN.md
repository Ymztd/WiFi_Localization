# LOS Experiment Studio User Manual

## 1. Purpose and experiment sequence

The project studies weak direct-path identifiability, candidate selection, waveform recovery, and the propagation of observation errors into position estimates. The GUI uses English labels.

| Stage | Research question | Evidence to inspect |
|---|---|---|
| Two-path baseline | Effects of delay gap, angle gap and relative power | True and reconstructed I/Q waveforms and delay response |
| Specular reflections | Misses, wrong selections and recovery errors under geometric reflections | Candidates, AoA/ToA tracks and LOS NMSE |
| 3GPP InF channels | Behavior under stochastic factory channels | Native LOS/NLOS state, track behavior and error distributions |

## 2. Requirements and startup

The project has been checked on Windows with MATLAB R2024a. The first two stages run independently. Stage 3 requires a separate QuaDRiGa installation and a quadriga_src folder containing @qd_layout.

Change the MATLAB current directory to this project and run the entry point.

~~~matlab
pos_gui
~~~

The default QuaDRiGa path retains the original machine's installation path. On another machine, supply the actual folder explicitly.

~~~matlab
pos_gui('D:/your/path/quadriga_src')
~~~

The QuaDRiGa folder button can also change the installation path. Configuration folder selects the directory containing the five bundled InF profiles. Stages initialize when first opened. Switching stages pauses hidden playback.

## 3. Basic workflow

1. Select the experiment stage and scenario.
2. Double-click the Value column in Scene and radio to edit settings.
3. Click Generate / Update channel.
4. Move the frame slider or use Play and Pause.
5. Open Waveform recovery and select an estimator.
6. Inspect the candidate table, Track metrics, LOS Diagnostics, LOS Failure boundary, Known LOS Experiment or Observation contribution.
7. Regenerate after changing physical parameters. Changing the estimator recomputes its estimates.

The nine plots show true LOS, the coherent sum of true NLOS, noisy reception, the estimated LOS candidate, the sum of remaining reconstructed candidates, a path schematic, and power/AoA/delay tracks. Scatterer connections in stochastic scenes serve as schematic geometry.

## 4. Parameters and units

| Setting | Meaning |
|---|---|
| BS Position, UE Start, UE End | x y z coordinates in metres |
| Carrier | GHz |
| Bandwidth | Total bandwidth in MHz |
| Tones | Number of frequency samples |
| BS / UE Antennas | Transmit and receive element counts |
| Total TX power | Transmit-power reference for the beamformed observation in dBm |
| UE Noise figure | dB |
| BS Manual scan angles | Starting and ending TX scan angles in degrees |
| Frames, Track duration | Snapshot count and duration in seconds |
| Random seed | Seed for channel and noise generation |

Element spacing is 0.45 wavelengths. The unambiguous delay interval is Tones divided by bandwidth in Hz. Increase Tones or reduce bandwidth if a path exceeds this interval.

Manual start/end uses the specified scan endpoints. Automatic scanning uses simulated path ground truth to choose a competing reflected direction and is an experimental control. A fixed 0 0 beam reduces scanning-null effects in the power curve.

Box attenuation applies additional loss only to direct rays intersecting the specified box. It is a controlled attenuation mechanism. It generates no extra box reflections.

## 5. Factory presets and link conditions

| Scenario | Hall dimensions m | Clutter density | Clutter height m | Clutter size m | Default BS / UE height m |
|---|---|---|---|---|---|
| InF-SL | 120 × 60 × 10 | 20% | 2 | 10 | 1.5 / 1.5 |
| InF-SH | 300 × 150 × 10 | 20% | 2 | 10 | 8 / 1.5 |
| InF-DL | 300 × 150 × 10 | 60% | 6 | 2 | 1.5 / 1.5 |
| InF-DH | 120 × 60 × 10 | 60% | 6 | 2 | 8 / 1.5 |
| InF-HH | 120 × 60 × 10 | 20% | 2 | 10 | 8 / 7 |

SL/SH/DL/DH use scenario and calibration presets from TR 38.901 Tables 7.2-4 and 7.8-7. HH dimensions, density and numerical heights are illustrative project choices. The current GUI uses fixed clutter presets. Selecting a scenario updates antenna heights.

L requires BS below clutter, while H requires BS above clutter. UE is below clutter in the first four scenarios. HH places both ends above clutter. Heights must lie between ground and ceiling. The 1.5 m BS height is a default that can be edited within the selected scenario's constraints.

Factory link supports LOS, NLOS and Auto. HH supports LOS only. Auto draws one link state from the LOS probability at the starting location and holds it over the track. Hall volume and surface area determine the delay-spread mean. GUI native NLOS adds no artificial direct ray.

The legacy study_los_failures batch retains a NLOS background with an added physical LOS. Its channel interpretation differs from the GUI's native NLOS. Programmatic inf_channel_run callers should set addPhysicalLos explicitly when using legacy profile names.

## 6. Estimators and comparison conditions

| Estimator | Input and implementation |
|---|---|
| OMP | Beamformed receive CSI, earliest detected candidate |
| SPRING+ | CSI path extraction and cross-frame association, with limited history at the start |
| M³ | Per-port MIMO pilots, subspace initialization and SAGE, followed by the GUI earliest-candidate rule |
| Radio SLAM | Per-port MIMO pilots, a synthetic two-sided beam power map, candidate gates and simplified synchronized 2D geometry |

The last three are paper-inspired adaptations. SPRING+ omits the full FTM positioning chain. M³ omits the original full multichannel localization chain. Radio SLAM omits full joint UE-state and map estimation.

Radio SLAM defaults require a LOS candidate to lie within 1 m of the earliest detected candidate and within 3 dB of the strongest extracted candidate. Candidate power comes from its own two-sided beam search. The main power plot uses the current TX beam. These power definitions differ.

Record observation access, pilot overhead, bandwidth, array size, seed, frame and thresholds when comparing methods. Overlapping plotted curves may still contain nonzero numerical errors.

## 7. Metrics and interpretation

los_quality_metrics uses these default criteria.

- Parameter match requires absolute delay error at most 1 ns and angular error at most 3 degrees.
- Waveform recovery requires complex LOS waveform NMSE at most −10 dB.
- Joint success requires both criteria.

The GUI label LOS Correct selection computes a parameter-window match. Unique physical path identity requires additional evidence. AoA error warning tolerance controls graphical warnings independently of the 3-degree metric threshold.

Estimated NLOS sums the remaining extracted components. A near-zero plot can result from missing candidates. Zero or absent true LOS energy makes some comparisons inapplicable.

## 8. Observation contribution and positioning errors

Observation contribution shows angle-only and range-only bands, paired-error position scatter, paired residuals, the original error sequence, and an empirical position-error CDF.

Track residuals transfers actual paired range/angle residuals from multiple frames to the chosen reference geometry. Frames vary in channel and geometry and retain dependencies. The view describes error propagation. Recovery gains require matched before/after experiments.

Run noise trials freezes the current physical channel and regenerates receiver noise. OMP uses one packet per trial. SPRING+ uses a frozen three-packet burst and evaluates the third packet. M³ and Radio SLAM currently support track-residual analysis only.

Projection assumes a known height difference, the positive x half-space relative to BS, and a ULA projected angle. Invalid geometry is counted and excluded from the position scatter. Radial and tangential errors can conceptually guide range/angle improvements, but this GUI does not separately report those components or compute Fisher information or CRLB.

## 9. Export, batch studies and validation

Export.mat saves current channel data and parameters. Export power writes a power image. Observation contribution exports paired residuals and projected coordinates to CSV.

~~~matlab
study_wall_spacing('D:/results/walls')
study_los_failures('D:/results/failures', [723 724 725])
~~~

Create output directories first. Adjust the QuaDRiGa path inside study_los_failures to match the machine. Batch runs may take substantial time.

~~~matlab
validate_pos_gui
validate_observation_view
~~~

validate_pos_gui(true) runs its GUI checks only. Validation creates screenshots and outputs in validation, so these files may reappear after cleanup. Validation creates and closes test figures. Save ongoing experiments before running it.

## 10. Code navigation

pos_gui.m is the entry point. inf_factory_preset.m and inf_factory_link.m resolve factory conditions. inf_channel_run.m generates observations. specular_channel_setup.m builds geometric reflections. Estimators reside in inf_waveform_fit.m, inf_spring_plus_fit.m and inf_paper_los_fit.m.

factory_localization_demo.m retains a compatibility entry. two_path_separation_demo.m provides an offline two-path study. study_*.m are batch studies and validate_*.m are regression checks. Runtime operation requires no preview PNGs, historical ZIP archives, internal backups or validation screenshots.

If MATLAB resolves an older same-name file, use which pos_gui -all to inspect its path and rerun from this project directory.

## 11. Standard reference

Factory settings reference 3GPP TR 38.901 V18.0.0 Tables 7.2-4, 7.4.2-1, 7.5-6 and 7.8-7.

[Official standard PDF](https://www.etsi.org/deliver/etsi_tr/138900_138999/138901/18.00.00_60/tr_138901v180000p.pdf)
