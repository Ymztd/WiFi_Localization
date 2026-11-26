# LOS Experiment Studio

MATLAB 弱 LOS 识别与恢复实验平台，按两径、多径反射、3GPP 工厂信道逐步展开。

A MATLAB experiment studio for weak LOS selection and recovery, covering two-path, specular and 3GPP factory channels.

~~~matlab
pos_gui
% Supply your QuaDRiGa quadriga_src folder for stage 3.
pos_gui('D:/your/path/quadriga_src')
~~~

- [中文版手册](MANUAL_ZH.md)
- [English manual](MANUAL_EN.md)

GUI 使用英文。前两个阶段无需 QuaDRiGa，第三阶段需配置实际安装路径。算法为改编实现，输入条件与指标定义见手册。

The GUI uses English. Stages 1–2 run independently. Stage 3 requires QuaDRiGa. Consult the manuals for estimator adaptations, observation access and evaluation definitions.
