# LOS 实验平台使用手册

## 1. 用途与实验顺序

本工程用于研究弱直达径 LOS 在多径环境中的可分辨性、候选选择、波形恢复，以及观测误差对定位的影响。GUI 文字采用英文。

建议按两径简单场景、多径反射场景、3GPP 工厂场景的顺序进行实验。

| 阶段 | 主要问题 | 重点查看 |
|---|---|---|
| Two-path baseline | 时延、角度间隔及功率差如何影响路径估计 | 真值与重建 I/Q 波形、时延响应 |
| Specular reflections | 几何反射如何引起漏检、误选及恢复误差 | 候选、AoA/ToA 轨迹、LOS NMSE |
| 3GPP InF channels | 上述问题在随机工厂信道中的表现 | 原生 LOS/NLOS、跨帧表现、观测误差分布 |

## 2. 环境与启动

已在 Windows、MATLAB R2024a 下验证。前两个阶段可独立运行。第三阶段需要单独安装 QuaDRiGa，并使用包含 @qd_layout 的 quadriga_src 目录。

在 MATLAB 中进入本工程目录，然后运行以下命令。

~~~matlab
pos_gui
~~~

默认 QuaDRiGa 路径沿用原工程的本机路径。其他机器应显式传入实际安装位置。

~~~matlab
pos_gui('D:/your/path/quadriga_src')
~~~

也可在第三阶段使用 QuaDRiGa folder 按钮更换路径。Configuration folder 应指向包含本工程五个 InF 配置文件的目录。GUI 窗口按需初始化各阶段，切换阶段时会暂停隐藏阶段的播放。

## 3. 基本操作

1. 选择实验阶段与场景。
2. 在 Scene and radio 中双击 Value 列修改参数。
3. 点击 Generate / Update channel 生成信道。
4. 使用时间滑块查看帧，或使用 Play、Pause。
5. 点击 Waveform recovery 进入九图视图，再选择估计方法。
6. 打开候选表、Track metrics、LOS Diagnostics、LOS Failure boundary、Known LOS Experiment 或 Observation contribution。
7. 修改物理参数后重新生成信道。单纯切换算法会重新计算对应估计结果。

九图依次显示真实 LOS、真实 NLOS 相干和、带噪接收、估计 LOS、其余候选重建和、路径示意，以及功率、AoA、时延轨迹。路径示意中的随机散射簇连线用于解释传播几何。

## 4. 参数与单位

| 界面参数 | 含义 |
|---|---|
| BS Position、UE Start、UE End | 三维坐标 x y z，单位 m |
| Carrier | 载频，GHz |
| Bandwidth | 总带宽，MHz |
| Tones | 频率采样点数 |
| BS / UE Antennas | 发射、接收阵元数 |
| Total TX power | 波束合成观测的发射功率标定，dBm |
| UE Noise figure | 噪声系数，dB |
| BS Manual scan angles | 发射扫描起止角，度 |
| Frames、Track duration | 帧数与轨迹持续时间，s |
| Random seed | 信道及噪声的随机种子 |

阵元间距采用 0.45 波长。时延的非模糊区间为 Tones / 带宽，带宽用 Hz。出现路径超出时延区间的错误时，增加 Tones 或降低带宽。

Beam 中 Manual start/end 使用手动起止角。自动扫描使用仿真路径真值寻找竞争反射方向，是受控实验设置。固定 0 0 波束可减少扫描零陷对功率曲线的影响。

Box attenuation 的附加损耗仅作用于穿过盒体的直达径。它是人工设置的遮挡控制。它不生成新的障碍物反射径。

## 5. 工厂场景与链路状态

| 场景 | 厂房长宽高 m | 杂物占地率 | 杂物高 m | 杂物尺寸 m | 默认 BS / UE 高 m |
|---|---|---|---|---|---|
| InF-SL | 120 × 60 × 10 | 20% | 2 | 10 | 1.5 / 1.5 |
| InF-SH | 300 × 150 × 10 | 20% | 2 | 10 | 8 / 1.5 |
| InF-DL | 300 × 150 × 10 | 60% | 6 | 2 | 1.5 / 1.5 |
| InF-DH | 120 × 60 × 10 | 60% | 6 | 2 | 8 / 1.5 |
| InF-HH | 120 × 60 × 10 | 20% | 2 | 10 | 8 / 7 |

SL/SH/DL/DH 采用 TR 38.901 表 7.2-4 和 7.8-7 的场景及校准预设。HH 的具体尺寸、密度和高度为本实验选值。当前 GUI 使用固定杂物预设，切换场景会更新天线高度。

L 要求 BS 低于杂物，H 要求 BS 高于杂物。前四类 UE 低于杂物，HH 收发两端均高于杂物。所有天线均应位于地面和天花板之间。1.5 m 是低基站的默认值，可修改为满足场景约束的其他高度。

Factory link 提供 LOS、NLOS、Auto。HH 仅提供 LOS。Auto 在轨迹起点按 LOS 概率抽样一次，整条轨迹保持该状态。厂房体积与表面积进入时延扩展参数。GUI 原生 NLOS 不额外叠加直达径。

旧批处理 study_los_failures 保留了“NLOS 背景加人工 LOS”的历史实验，其信道含义与当前 GUI 的原生 NLOS 不同。程序化调用 inf_channel_run 时，应显式设置 addPhysicalLos，避免依赖旧接口的默认行为。

## 6. 算法与公平比较

| 方法 | 输入与当前实现 |
|---|---|
| OMP | 波束合成后的接收 CSI，最早检测候选作为 LOS |
| SPRING+ | CSI 路径估计与跨帧关联，前三帧需注意历史不足 |
| M³ | 逐端口 MIMO 导频、子空间初始化与 SAGE，GUI 使用最早候选规则 |
| Radio SLAM | 逐端口 MIMO 导频形成双端波束功率图，结合距离、功率门限与简化二维几何选择 |

后三者均为基于论文思路的改编。SPRING+ 未实现完整 FTM 定位，M³ 未实现原论文完整多信道定位流程，Radio SLAM 未实现完整的终端状态与地图联合求解。

Radio SLAM 默认 LOS 候选门限为距最早候选 1 m 内，功率距最强已提取候选 3 dB 内。其候选功率来自自身双端波束扫描。主界面的功率曲线来自当前发射波束，两者不能直接等同。

比较算法时应记录各自输入、导频开销、带宽、阵元数、种子、帧及门限。仅看到曲线重合无法证明误差严格为零。

## 7. 成功判据与图的含义

代码 los_quality_metrics 默认采用下列阈值。

- 参数匹配，时延误差绝对值不超过 1 ns，角度误差绝对值不超过 3°。
- 波形恢复，复数 LOS 波形 NMSE 不超过 −10 dB。
- 联合成功，同时满足以上两项。

GUI 中 LOS Correct selection 的计算实质是参数窗口匹配，无法单独证明唯一的物理路径身份。AoA error warning tolerance 控制图中提示，独立于上述 3° 评估阈值。

Estimated NLOS 是其余已提取候选的重建和。它接近零可能表示候选缺失，不能据此认定反射已全部消除。真实 LOS 能量为零或不存在时，部分指标显示 N/A。

## 8. 观测贡献与定位误差

Observation contribution 显示角度约束、距离约束、联合位置散点、成对参数误差、误差序列及位置误差 CDF。

Track residuals 将各帧实际成对的距离和角度残差转换到所选参考帧。样本来自不同信道和几何位置，相关性仍然存在。该视图用于描述误差传播。恢复收益需在相同条件下进行恢复前后对照。

Run noise trials 固定当前帧物理信道并重复生成接收噪声。支持 OMP 与 SPRING+，SPRING+ 每次使用三包冻结信道观测并取第三包结果。M³ 和 Radio SLAM 当前只提供轨迹残差视图。

投影假设高度差已知且 UE 位于 BS 的正 x 半空间，采用 ULA 投影角。非法几何会计入 invalid geometry，不进行裁剪。用户可利用径向、切向误差的思路判断测距或测角优化重点，但当前界面尚未单独输出这两个分量，也未计算 Fisher 信息或 CRLB。

## 9. 导出、批处理与验证

Export.mat 保存当前信道和参数，Export power 导出功率图，Observation contribution 中的 Export CSV 导出成对残差及参考几何下的位置。

~~~matlab
study_wall_spacing('D:/results/walls')
study_los_failures('D:/results/failures', [723 724 725])
~~~

先建立输出目录。study_los_failures 内的 QuaDRiGa 路径需要按本机环境调整。批处理可能耗时较长。

~~~matlab
validate_pos_gui
validate_observation_view
~~~

validate_pos_gui(true) 只运行 GUI 验证部分。验证脚本会在 validation 目录重新生成截图与输出，发布时已删除的图片可能因此再次出现。执行验证会创建、关闭测试窗口，建议在保存当前实验后运行。

## 10. 代码导航与维护

入口为 pos_gui.m，工厂配置在 inf_factory_preset.m 和 inf_factory_link.m，信道计算在 inf_channel_run.m，几何反射在 specular_channel_setup.m，恢复方法在 inf_waveform_fit.m、inf_spring_plus_fit.m 和 inf_paper_los_fit.m。

保留 factory_localization_demo.m 作为兼容入口，two_path_separation_demo.m 作为离线两径实验。study_*.m 用于批处理，validate_*.m 用于回归。工程运行不依赖预览 PNG、历史 ZIP、内部旧备份或验证截图。

修改后的源代码需保存。MATLAB 若加载同名旧文件，可用 which pos_gui -all 检查路径，再进入本工程目录重新运行。

## 11. 协议依据

工厂场景参照 3GPP TR 38.901 V18.0.0 的表 7.2-4、7.4.2-1、7.5-6 和 7.8-7。

[官方协议 PDF](https://www.etsi.org/deliver/etsi_tr/138900_138999/138901/18.00.00_60/tr_138901v180000p.pdf)
