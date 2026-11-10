# SpektraCam — iPhone 13 Pro Max 物理光谱与感光化学胶片摄影/摄像系统深度研发报告与架构白皮书

## 1. 物理胶片模拟全生态深度调研（Milestone 1）

### 1.1 开源项目深度代码解构（核心聚焦 `spektrafilm` 生态及多端加速架构）

#### 1.1.1 `andreavolpato/spektrafilm`（前身 `agx-emulsion`）核心管线解构

由瑞典皇家理工学院（KTH）研究员 Andrea Volpato 发起的开源项目 [andreavolpato/spektrafilm](https://github.com/andreavolpato/spektrafilm)（早期版本命名为 `agx-emulsion`，详见 [discuss.pixls.us 首发研究帖](https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209)）摒弃了经验性 3D LUT 与传统 RGB 曲线微调，首次将厂商发布的分光光度测量手册（如 Kodak Portra 400 Datasheet E-4050、Kodak Portra Endura Datasheet E-4021）转化为端到端的计算感光化学模型。其核心架构由三大子包组成：`src/spektrafilm`（纯物理运行时管线，接收场景线性光并输出线性光）、`src/spektrafilm_gui`（基于 Qt 与 `napari` 的交互式数字暗房）以及 `src/spektrafilm_lut_creator`（支持 1-LUT 至 4-LUT 拓扑与 OCIO v2 配置导出的预积分烘焙器）。

在 [andreavolpato/spektrafilm](https://github.com/andreavolpato/spektrafilm) 的核心计算模块 `emulsion.py` 中，单帧图像的胶片曝光与显影严格遵循五步张量缩并流：

1. **光谱网格与采样步长（Spectral Binning）**：在 `config.py` 中定义 `SPECTRAL_SHAPE = colour.SpectralShape(380, 780, 5)`，即在 $380\text{–}780\,\text{nm}$ 可见光谱域内以 $5\,\text{nm}$ 步长划分为 $N_\lambda = 81$ 个离散波长分箱（在实时或低内存分支中可降采样至 $10\,\text{nm}$ 步长即 41 个波长箱）。研究证实，在从厂商 Datasheet 反混叠（Unmixing）拟合染料吸收峰时，$5\,\text{nm}$ 步长能完整保留青（$\sim 665\,\text{nm}$）、品红（$\sim 548\,\text{nm}$）、黄（$\sim 445\,\text{nm}$）主吸收峰与次级寄生吸收谷，防止 $10\,\text{nm}$ 粗网格造成的色相阶跃。

2. **厂商 Datasheet 反混叠（Unmixing）与橙色掩膜耦合剂（Masking Couplers）**：胶片厂商公布的密度曲线通常使用 Status M（针对彩负）或 Status A（针对反转片与相纸）三色密度计测得，包含严重的层间光谱串扰（Cross-talk）。`spektrafilm` 首先对原始数据进行通道解耦，使 H-D 特征密度曲线 $D_k(\log_{10} H_k)$（$k \in \{R, G, B\}$）独立对应单一卤化银感光层的成色剂产率。更为关键的是，彩色负片未曝光区域呈现浓烈的橙黄色片基（Orange Mask），这是因为品红染料在蓝光区、青染料在蓝绿光区存在非理想的寄生吸收。为抵消这种寄生吸收，乳剂中加入了带颜色的**掩膜耦合剂（Masking Couplers）**：未曝光时掩膜耦合剂自身吸收蓝/绿光；曝光显影生成品红或青染料时，掩膜耦合剂按化学计量比被消耗。在数学模型中，`spektrafilm` 将掩膜耦合剂建模为独立染料光谱曲线 $d_{C,M,Y}(\lambda)$ 在 $430\text{–}550\,\text{nm}$ 波段的**负向吸收分量（Negative Absorption Contribution）**，叠加恒定的片基最小密度 $D_{\min}(\lambda)$，从而在暗房放大印相时天然消除串扰并还原高纯度色彩。

3. **显影抑制剂释放成色剂（DIR Couplers）与 Eberhard 邻接边缘效应**：仅依赖 Datasheet 中的静态 H-D 曲线与染料光谱无法复现真实胶片的高色彩纯度与锐利边缘。现代彩色负片通过 **DIR Couplers（Developer Inhibitor Releasing Couplers）** 在高曝光密度生成区局部释放显影抑制剂离子（如巯基四氮唑或苯并三氮唑离去基团）。抑制剂向同层邻域及相邻感色层扩散：

   * **层间垂直扩散（Interlayer Chemical Inhibition）**：通过 $3\times 3$ 抑制矩阵 $\mathbf{M}_{\text{DIR}}$ 削减其余两层的有效密度或有效对数曝光量，拉开通道差值，显著提升高饱和色块的色纯度。

   * **层内水平扩散（Intralayer Spatial Diffusion / Eberhard Effect）**：抑制剂在明暗交界处由高密度侧向低密度侧进行微米级高斯扩散（物理半径 $r_{\text{DIR}} \in [5, 50]\,\mu\text{m}$，由像素物理尺寸 `pixel_size_um` 换算为像素半径 $\sigma_{\text{px}}$），利用高斯拉普拉斯差分 $\Delta D = D - G_{\sigma_{\text{px}}} * D$ 在高密度边缘形成高反差 Mackie 线，提升微观锐度（Acutance）。

4. **多子层随机粒子颗粒模型（Stochastic Multi-Sublayer Grain Model）**：现代彩色负片（如 Kodak Portra 400 与 Vision3 系列）的每个感色层均由 2 至 3 个不同感光度（Fast / Mid / Slow）的卤化银乳剂子层复合而成，以扩展曝光宽容度。`spektrafilm` 模拟了这一微观物理结构：高速子层银盐晶粒直径更大（消费级胶片粒径处于 $0.2\text{–}2.0\,\mu\text{m}$，对应投影面积 $0.03\text{–}3.2\,\mu\text{m}^2$，且晶粒面积近似正比于胶片 ISO），在低至中等曝光区产生较粗颗粒；慢速子层晶粒细密，填充高曝光区。在每个像素的面积单元 $A_{\text{pixel}} = (\text{pixel\_size\_um})^2$ 内，晶粒数目服从二项分布/泊松分布（Binomial/Poisson），显影转化为离散的偶氮甲碱/吲哚苯胺**染料云（Dye Clouds）**。该模型严格复现了 Kodak Vision3 50D Datasheet 中的实测 RMS 颗粒度随曝光量变化的双峰/三峰特征曲线。

5. **虚拟暗房放大机（Dichroic Enlarger）与预闪光（Pre-flashing）**：冲洗后的虚拟负片在 $3200\,\text{K}$ 卤素光源下经青/品红/黄（C/M/Y）双色干涉滤光片（Dichroic Filters）调制光谱，依据 Beer-Lambert 定律计算透射光谱，投射至 RA-4 相纸（如 Kodak Endura Premier、Fujifilm Crystal Archive Type II）或电影印片正片（Kodak 2383）。由于相纸宽容度窄、反差高（$\gamma_{\text{paper}} \approx 2.4\text{–}2.9$），`spektrafilm` 引入了暗房经典的预闪光（Pre-flashing）技术：在投影负片前或后，隔着未曝光片基对相纸施加微量均匀基底曝光 $E_{\text{preflash}}$（可独立叠加滤色片微调色偏），将相纸高光区推过 H-D 曲线趾部（Toe）死区，从而在不损失主体阶调的前提下找回天空与高光细节。

#### 1.1.2 跨平台与移动端衍生生态横向剖析

为了解决 Python 原型处理单张 6MP 图像耗时约 10 秒、处理全尺寸 RAW 消耗数十 GB 内存的瓶颈，开源社区围绕 `spektrafilm` 构建了五大高性能 C++/GPU 移植分支：

| 开源项目 / 分支 | 核心计算后端与精度 | 光谱加速与预积分策略 | 关键工程特征与移动端启示 | 
| ----- | ----- | ----- | ----- | 
| [andreavolpato/spektrafilm](https://github.com/andreavolpato/spektrafilm) | Python (`numpy` / `scipy` / `colour-science`)，`float64` | 逐像素 81 波段（5nm）或 41 波段（10nm）全张量缩并 | 物理参考基准（Oracle），包含完整的反混叠建库脚本与 `spektrafilm_lut_creator` | 
| [thetechgeekko/Spectrafilmandroid](https://github.com/thetechgeekko/Spectrafilmandroid) | Android NDK C++17 (`float64` 严格参考路) + Vulkan Compute (`float32` 实时路) | 采用 `Hanatos2025` 光谱升采样表，GPU 与 CPU 双路由自动校验回退 | 建立了 44 组黄金测试向量（Golden Vectors），各阶段与 Python Oracle 误差小于 $1.1\times 10^{-7}\text{–}5.6\times 10^{-7}$ | 
| [chaert-s/spektrafilm-ofx](https://github.com/chaert-s/spektrafilm-ofx) | Apple Metal (macOS 原生) + Vulkan Compute (Windows/Linux) | 构建时通过 Python 生成光谱/曲线查找表，GPU 执行空间卷积与 Beer-Lambert 积分 | 详见 [Lift Gamma Gain 讨论帖](https://www.liftgammagain.com/forum/index.php?threads/spektrafilm-ofx.19764/) 与 [xere.my 评测](https://xere.my/davinci-plugins/spektrafilm-ofx/)；支持 DaVinci Resolve 4K 实时回放与 8mm–70mm 画幅自适应 | 
| [vkdt filmsim 模块](https://jo.dreggn.org/vkdt/src/pipe/modules/filmsim/readme.html) | Vulkan GLSL Compute Shader (`float32`/`float16`) | 使用 `spectra-em.lut` 光谱升采样表 + 每款胶片 3 行 256 宽度的 `filmsim.lut` | 由 Johannes Hanika (`hanatos`) 编写，引入 Langmuir 等温吸附系数 `lang_r/g/b` 与片基多次反射衰减 `hal_bnc/hal_dec` | 
| [darktable spektrafilm 模块](https://discuss.pixls.us/t/spektrafilm-darktable-module-implementation-discussion/58744) | C + OpenCL Kernel | 预导出 `spectra_lut.f32` ($192\times 192\times 81$) 与 28 款胶片参数包 `pack.json` | 在桌面 GPU 上实现毫秒级实时响应，验证了“光谱升采样系数预表 + 实时通道显影”的高效性 | 
| [Unspektrawesome](https://www.reddit.com/r/spektrafilm/comments/1wdo3e9/unspektrawesome_an_android_port_spektrafilm/) & [storytold/lightcraft](https://github.com/storytold/lightcraft) | Vulkan / 纯 Rust 32-bit 浮点场景线性管线 | 取景器采用降分辨率/预积分密度场保证 30fps 预览，后台全尺寸 RAW 异步冲洗 | 参见 [LightCraft Issue #988](https://github.com/storytold/lightcraft/issues/988) 与 [Issue #380](https://github.com/storytold/lightcraft/issues/380)，确立了移动端实时相机“取景器实时轻量化 + 静态全光谱精算”的双轨范式 | 

### 1.2 商业级物理胶片软件与 App 逆向对标

通过对影视工业与专业摄影领域的四大商业标杆进行逆向剖析，可以清晰提炼出各自在影调压缩、防光晕反射与色相随密度偏移（Hue-vs-Density Twist）上的核心差异：

| 商业软件标杆 | 核心管线拓扑架构 | 高光/暗部滚降（Shoulder/Toe）与色相扭转机制 | 空间光学与颗粒实现机制 | 
| ----- | ----- | ----- | ----- | 
| [Video Village Filmbox Pro](https://videovillage.com/learn/filmbox/full-guide/grading-with-filmbox) | `Camera → Negative → Lab → Print → Display`（支持拆分为 Pre-Grade 与 Post-Grade 双节点） | 基于物理分光光度测量的连续相对色彩关系建模，高光进入负片肩部时因三层乳剂饱和速度差异产生自然的暖向色相弯曲 | 区分短程乳剂内光学散射（Optical Diffusion）与长程片基反射红晕（Halation），配备真实胶片扫描颗粒引擎 | 
| [Dehancer Pro / Dehancer iOS](https://www.dehancer.com/features) | `Camera Log → Film Developer → Push/Pull → Halation/Bloom → Print (2383/3513/Endura) → CMY Head → Grain` | 在暗房对 60+ 款胶片与相纸进行多档欠曝/过曝实拍采样；配备专门的 `Film Compression` 模块独立控制白点与高光肩部压缩斜率 | 独立建模 `Halation`（红敏层二次曝光与 `Defringe` 色差消除）、`Bloom`（镜头弥散高光辉光）、`Film Breath`（帧间密度/色温微抖动）与 `Gate Weave`（片门机械晃动） | 
| [Cullen Kelly Genesis](https://cullenkellycolor.com/genesis) | 秉承 Steve Yedlin ASC 理念的纯光化学过程建模：`Scene Linear → Negative Exposure → Lab Development / Bleach Bypass → Print Stock` | 详见 [Mixing Light 深度评测](https://mixinglight.com/color-grading-tutorials/deep-dive-cullen-kelly-genesis-plugin/)；不依赖相机匹配 LUT，强调正片印制（2383）陡峭 S 型曲线带来的高光去饱和与暗部青蓝冷调沉淀 | 在负片化学密度空间而非显示 RGB 空间注入颗粒与光晕，支持留银冲洗（Bleach Bypass）带来的银盐高反差消色差叠加 | 
| [FilmConvert Nitrate](https://www.filmconvert.com/nitrate) | `Camera Profile Pack (Log->Intermediate) → Negative Stock Curve → 3-Way Wheel → Grain Curve → Halation` | 强绑定特定相机传感器的色彩矩阵与对数曲线（详见 [FilmConvert 教程](https://www.filmconvert.com/tutorials?product=nitrate&software=ofx)），允许用户自定义调整高光肩部与暗部趾部的曲线张力 | 提供可交互编辑的 `Grain Curve`（独立调节高光、中间调、暗部的颗粒权重）与后置双通道 Halation | 

**关键技术洞察**：静态 3D LUT 之所以在极端高光（如霓虹灯管、逆光树叶、日落云层）下出现明显的“色阶断层（Banding）”或“塑料感死白”，根本原因在于静态 LUT 将空间域的光学散射（Halation/Bloom/DIR Eberhard 边缘）与色彩域的非线性减色法吸收割裂开来。在真实胶片中，高光处的防光晕反射与乳剂散射发生在**负片感光层积分之后、H-D 显影曲线非线性压缩之前**；散射开的高能红光与绿光会推动周围像素的红/绿感光层跨过阈值，在经由 RA-4 相纸或 2383 正片冲洗反转后，自然呈现出中心白亮、内缘金黄、外缘橘红的连续色相渐变（Hue-vs-Density Twist）。

### 1.3 底层物理光学与感光化学论文综述与数学推导

#### 1.3.1 光谱重建（Spectral Upsampling）：Jakob & Hanika (Eurographics 2019)

根据 Wenzel Jakob 与 Johannes Hanika 发表的经典论文 [A Low-Dimensional Function Space for Efficient Spectral Upsampling (Eurographics 2019)](https://rgl.epfl.ch/publications/Jakob2019Spectral)（[论文全文 PDF](https://jo.dreggn.org/home/2019_sigmoid.pdf) 及官方参考实现 [mitsuba-renderer/rgb2spec](https://github.com/mitsuba-renderer/rgb2spec)），自然界绝大多数物体表面的反射光谱 $S(\lambda) \in [0, 1]$ 都是光滑且受能量守恒约束的。该研究提出利用一个三参数二次多项式复合代数 Sigmoid 函数来紧致表示连续反射光谱：

$$
S(\lambda) = s\left(c_0 \lambda^2 + c_1 \lambda + c_2\right), \quad \text{其中 } s(x) = \frac{1}{2} + \frac{x}{2\sqrt{1 + x^2}}
$$

**从 Apple Wide Gamut P3 / Rec.2020 线性三刺激值求取** $(c_0, c_1, c_2)$ **的完整工程流程**：

1. **高动态范围亮度分离（Energy-Conserving Albedo Decomposition）**：由于相机传感器采集的 Scene-Linear RGB 值 $C = (R, G, B)$ 在高光处可能远大于 $1.0$（例如 iPhone 13 Pro Max 在 10-bit HLG 或 12-bit ProRAW 下高光可达 $8.0\text{–}16.0$），而物理反射率函数 $s(\cdot)$ 严格有界于 $(0, 1)$，因此首先提取像素能量包络比例因子：

   $$
   \alpha = \max\left(1.0,\, 1.05 \times \max(R, G, B)\right), \quad \tilde{C} = (\tilde{R}, \tilde{G}, \tilde{B}) = \frac{C}{\alpha} \in (0, 0.952]
   $$

2. **三维预计算系数表（Offline Levenberg-Marquardt Tabulation）与解析快速求解**：

   * 在离线预计算工具（如 [mitsuba-renderer/rgb2spec](https://github.com/mitsuba-renderer/rgb2spec)）中，将色空间按主通道最大值 $m = \max(\tilde{R}, \tilde{G}, \tilde{B})$ 划分为 3 个立方体分支，采用平滑非线性映射 $\tilde{z} = \text{smoothstep}(z)$ 离散化为 $3 \times 64 \times 64 \times 64$ 网格；对每个网格点通过 Levenberg-Marquardt 迭代求解使重构光谱在 CIE D65 光源与 CIE 1931 标准观察者 $\bar{x}(\lambda), \bar{y}(\lambda), \bar{z}(\lambda)$ 下严格还原目标 RGB。

   * 在移动端实时计算或无外部大体积 LUT 依赖的着色器中，可将归一化波长定义为 $u = \frac{\lambda - 380}{400} \in [0, 1]$，利用蓝（$u_B = 0.16 \Rightarrow 444\,\text{nm}$）、绿（$u_G = 0.41 \Rightarrow 544\,\text{nm}$）、红（$u_R = 0.66 \Rightarrow 644\,\text{nm}$）三个特征锚点的逆 Sigmoid 映射 $y_k = s^{-1}(\tilde{C}_k) = \frac{\tilde{C}_k - 0.5}{\sqrt{\tilde{C}_k(1 - \tilde{C}_k)}}$，直接通过二阶拉格朗日插值闭式解出 $(c_0, c_1, c_2)$：

     $$
     c_0 = 8\left(y_B - 2y_G + y_R\right), \quad c_1 = 4\left(y_R - y_B\right) - 0.82\,c_0, \quad c_2 = y_G - 0.1681\,c_0 - 0.41\,c_1
     $$

   * 最终像素在波长 $\lambda$ 处的辐射光谱能量为 $L(\lambda) = \alpha \cdot I_{\text{scene}}(\lambda) \cdot s\left(c_0 u(\lambda)^2 + c_1 u(\lambda) + c_2\right)$。每个波长采样仅需 6 条浮点乘加与 1 条快速平方根倒数指令 `rsqrt`，非常适合 Apple A15 GPU 的 SIMD 向量单元。

#### 1.3.2 感光乳剂、显影化学与光学散射物理模型

结合 [MIPS Lab 彩色耦合剂冲印原理 (Ambra Cattaneo)](https://mips.di.unimi.it/wp/wp-content/uploads/2022/08/Dye-coupler-print.pdf)、Peter Bergthaller 发表的权威综述 [Couplers in colour photography—chemistry and function Part 1](https://www.researchgate.net/publication/288740475_Couplers_in_colour_photography-chemistry_and_function_Part_1) 与 [Part 2](https://www.researchgate.net/publication/289392801_Couplers_in_colour_photography-chemistry_and_function_Part_2)，以及 Frieser 光学散射理论，物理暗房管线的核心控制方程如下：

1. **乳剂光谱曝光积分（Spectral Exposure Integration）**：
   设第 $k \in \{R, G, B\}$ 层卤化银乳剂的光谱灵敏度为 $S_k(\lambda)$，镜头暗角遵循 $\cos^4\theta$ 定律，则像素 $(x, y)$ 处的原始感光积分为：

   $$
   E_k^{(0)}(x, y) = 2^{\text{EV}} \cdot \left(1 - w_{\text{vig}} + \frac{w_{\text{vig}}}{(1 + r(x,y)^2)^2}\right) \int_{380\text{nm}}^{780\text{nm}} L(x, y, \lambda)\, S_k(\lambda)\, \mathrm{d}\lambda
   $$

2. **Frieser 乳剂内散射 MTF 与片基防光晕层反射（Halation PSF）**：
   光线进入多层明胶乳剂时，首先经历卤化银微晶的米氏散射（Frieser 双指数点扩散函数 $\text{PSF}_{\text{scatter}}(r) = \frac{1}{2\pi r_s^2} e^{-r / r_s}$）；穿透蓝敏层、黄滤光层、绿敏层与红敏层的剩余强光到达三醋酸纤维素（TAC）或聚酯（PET）片基背面。若无碳黑防光晕层（Remjet，如 CineStill 800T/50D）或防光晕层被强光击穿，光线以大角度反射回底部的红敏层与中部的绿敏层，服从洛伦兹/双指数长尾分布：

   $$
   E_k(x, y) = \left(E_k^{(0)} * \text{PSF}_{\text{scatter}}\right)(x, y) + \eta_k \left[\left(E_k^{(0)} \cdot \Phi_{\text{hl}}(E_k^{(0)})\right) * \text{PSF}_{\text{hal}, k}\right](x, y) + \beta_{\text{bloom}} \left[\left(E_k^{(0)} \cdot \Phi_{\text{bloom}}\right) * G_{\sigma_{\text{bloom}}}\right](x, y)
   $$

   其中 $\eta_R \gg \eta_G \gg \eta_B$，$\sigma_{\text{hal}, R} \approx 200\text{–}285\,\mu\text{m}$。

3. **Hurter-Driffield (H-D) 特征方程与迫冲/减冲调制**：
   将散射后的曝光量取以 10 为底的对数 $H_k = \log_{10} E_k$。迫冲/减冲档位 $P \in [-2, +3]$、显影液温度偏差 $\Delta T = T - 37.8^\circ\text{C}$ 与搅动强度 $A_{\text{agit}}$ 共同调制特征曲线斜率 $\gamma_k$ 与最小灰雾密度 $D_{\min, k}$：

   $$
   \gamma_k' = \gamma_k \cdot 1.14^P \cdot (1 + 0.04\,\Delta T) \cdot A_{\text{agit}}, \quad D_{\min, k}' = D_{\min, k} + \max\left(0,\, 0.025\,P + 0.08\times 0.04\,\Delta T\right)
   $$

   $$
   D_k^{\text{raw}}(H_k) = D_{\min, k}' + \frac{D_{\max, k} - D_{\min, k}'}{1 + \exp\left(-\frac{4\,\gamma_k'}{D_{\max, k} - D_{\min, k}'}\left(H_k - H_{0, k}\right)\right)}
   $$

4. **DIR 成色剂化学抑制与 Eberhard 边缘微反差方程**：
   依据 [Bergthaller (2002)](https://www.researchgate.net/publication/288740475_Couplers_in_colour_photography-chemistry_and_function_Part_1) 阐述的偶联动力学与 [vkdt filmsim](https://jo.dreggn.org/vkdt/src/pipe/modules/filmsim/readme.html) 的 Langmuir 等温吸附模型，净生成密度 $\tilde{\mathbf{D}} = \mathbf{D}^{\text{raw}} - \mathbf{D}_{\min}'$ 受到 $3\times 3$ 层间矩阵 $\mathbf{M}_{\text{DIR}}$、邻域拉普拉斯算子（Eberhard 效应）与局部显影剂耗竭（Exhaustion）的联合调制：

   $$
   \mathbf{D}_{\text{neg}}(x, y) = \mathbf{D}_{\min}' + \frac{\mathbf{M}_{\text{DIR}}(w_{\text{cpl}})\,\tilde{\mathbf{D}}(x, y) + \kappa_{\text{edge}}\left(\mathbf{D}^{\text{raw}}(x, y) - \left(G_{\sigma_{\text{DIR}}} * \mathbf{D}^{\text{raw}}\right)(x, y)\right)}{1 + \xi_{\text{exh}} \cdot \overline{\tilde{D}}_{\text{surround}}(x, y)}
   $$

5. **Beer-Lambert 定律与暗房放大印相（Enlarger + RA-4 / 2383 Print）**：
   负片在每个波长 $\lambda$ 处的总光谱光密度为三层染料光谱与双色滤光片（C/M/Y Dichroic Wheel）的线性叠加：

   $$
   D_{\text{total}}(x, y, \lambda) = Q_{\text{Callier}} \sum_{k \in \{C, M, Y\}} \left(D_{\text{neg}, k}(x, y) + \delta D_{\text{grain}, k}(x, y)\right) d_{\text{neg}, k}(\lambda) + \sum_{f \in \{C, M, Y\}} c_f\, d_{\text{filter}, f}(\lambda)
   $$

   由 Beer-Lambert 定律求得负片光谱透射率 $T_{\text{neg}}(x, y, \lambda) = 10^{-D_{\text{total}}(x, y, \lambda)}$，乘以放大机光源光谱 $I_{\text{enl}}(\lambda)$ 并与相纸光谱灵敏度 $S_{\text{paper}, j}(\lambda)$ 积分，叠加预闪光 $E_{\text{preflash}}$ 后再次通过相纸 H-D 曲线与 Beer-Lambert 反射/透射积分，最终经 CIE 1931 标准观察者映射至 Apple Display P3 或 Rec.2020 HLG。

## 2. 物理暗房数学引擎设计、内置经典胶片数据库与全参数体系规范（Milestone 2）

### 2.1 内置 27 款实验室级经典胶片与印相材料参数总表

在工程源码 `Sources/Models/FilmStockDatabase.swift` 中，完整内置了 22 款摄影/电影底片与 5 款暗房相纸/电影正片的标准化实验室参数（涵盖感光度、参考色温、Remjet 防光晕层标志、三通道 $D_{\min}/D_{\max}/\gamma$、光谱峰值与半宽、蓝光串扰系数、掩膜耦合剂负吸收修正量、RMS 颗粒度、MTF50 空间频率、光晕反射率与 $3\times 3$ DIR 抑制矩阵）：

| 类别 | 内置型号 ID | 胶片 / 相纸名称 | ISO | 基准色温 | $\gamma_{R,G,B}$ 斜率 | RMS 颗粒度 | 核心物理与化学特性建模 | 
| ----- | ----- | ----- | ----- | ----- | ----- | ----- | ----- | 
| **C-41 彩负** | `kodak_portra_160` | Kodak Portra 160 | 160 | 5500K | $(0.58, 0.60, 0.62)$ | 9.0 | 低反差柔顺肩部、柔和DIR层间抑制，肤色过渡极细腻 | 
| **C-41 彩负** | `kodak_portra_400` | Kodak Portra 400 | 400 | 5500K | $(0.61, 0.63, 0.65)$ | 11.0 | 现代 Vision3 衍生微结构 T-Grain、宽广高光宽容度与暖调高光偏移 | 
| **C-41 彩负** | `kodak_portra_800` | Kodak Portra 800 | 800 | 5500K | $(0.64, 0.66, 0.68)$ | 14.0 | 高感光度大粒径卤化银子层，更高的暗部青品红分离度与适度红晕 | 
| **C-41 彩负** | `kodak_ektar_100` | Kodak Ektar 100 | 100 | 5500K | $(0.72, 0.74, 0.76)$ | 8.0 | 超细颗粒（RMS 8.0）、高斜率 $\gamma$ 与强 DIR 层间抑制矩阵（主对角 1.08–1.10） | 
| **C-41 彩负** | `kodak_gold_200` | Kodak Gold 200 | 200 | 5500K | $(0.68, 0.69, 0.65)$ | 12.5 | 蓝敏层斜率略低（0.65），高光与中间调呈现经典消费级金暖色调 | 
| **C-41 彩负** | `kodak_ultramax_400` | Kodak UltraMax 400 | 400 | 5500K | $(0.70, 0.71, 0.68)$ | 14.5 | 宽光谱灵敏度半宽与高对比度，明快鲜艳的红黄还原与明显颗粒质感 | 
| **C-41 彩负** | `fujifilm_pro_400h` | Fujifilm Pro 400H | 400 | 5500K | $(0.59, 0.63, 0.64)$ | 10.5 | 模拟第四感色层（505nm 青敏层）窄化绿蓝串扰，冷青色暗部与通透肤色 | 
| **C-41 彩负** | `fujifilm_superia_xtra_400` | Fujifilm Superia X-TRA 400 | 400 | 5500K | $(0.67, 0.70, 0.69)$ | 13.5 | 第四感色层消费级调校，翡翠绿树叶响应与品红阴影微偏 | 
| **ECN-2 电影负片** | `kodak_vision3_50d_5203` | Kodak Vision3 50D (5203) | 50 | 5500K | $(0.52, 0.53, 0.55)$ | 6.5 | ECN-2 低反差宽动态范围（$\gamma \approx 0.53$），带 Remjet 碳黑层抑制光晕 | 
| **ECN-2 电影负片** | `kodak_vision3_200t_5213` | Kodak Vision3 200T (5213) | 200 | 3200K | $(0.53, 0.54, 0.56)$ | 8.5 | 3200K 钨丝灯平衡电影负片，带 Remjet 防光晕层与高锐度 MTF50 (74 c/mm) | 
| **ECN-2 电影负片** | `kodak_vision3_250d_5207` | Kodak Vision3 250D (5207) | 250 | 5500K | $(0.54, 0.55, 0.57)$ | 9.5 | 好莱坞日景主力电影底片，配合 2383 印片正片呈现标杆级电影质感 | 
| **ECN-2 电影负片** | `kodak_vision3_500t_5219` | Kodak Vision3 500T (5219) | 500 | 3200K | $(0.55, 0.56, 0.58)$ | 11.5 | 好莱坞夜景/灯光主力底片，具备极宽的过曝肩部容忍度 | 
| **除碳电影负片** | `cinestill_800t` | CineStill 800T (Remjet-Free) | 800 | 3200K | $(0.63, 0.65, 0.67)$ | 12.8 | 5219 去除 Remjet 后经 C-41 交叉冲洗：反差提升且具备强烈红橙色片基光晕（$\eta_R = 0.095, \sigma_R = 285\,\mu\text{m}$） | 
| **除碳电影负片** | `cinestill_50d` | CineStill 50D (Remjet-Free) | 50 | 5500K | $(0.60, 0.61, 0.63)$ | 7.5 | 5203 除碳 C-41 冲洗版，兼顾超细颗粒与柔美温暖的高光红晕 | 
| **E-6/K-14 反转片** | `fujifilm_velvia_50` | Fujifilm Velvia 50 (RVP50) | 50 | 5500K | $(1.88, 1.92, 1.86)$ | 9.0 | 传奇风光正片：超高反差、极深 $D_{\max} \approx 3.6$ 与超强 DIR 耦合色彩饱和度 | 
| **E-6/K-14 反转片** | `fujifilm_provia_100f` | Fujifilm Provia 100F (RDPIII) | 100 | 5500K | $(1.65, 1.68, 1.64)$ | 8.0 | 标准专业反转片，微粒细腻（RMS 8.0），中性精准的高光与阴影还原 | 
| **E-6/K-14 反转片** | `fujifilm_astia_100f` | Fujifilm Astia 100F (RAP100F) | 100 | 5500K | $(1.52, 1.54, 1.50)$ | 7.0 | 柔和人像反转片，反转片中最柔和的肩部与趾部过渡 | 
| **E-6/K-14 反转片** | `kodak_ektachrome_e100` | Kodak Ektachrome E100 | 100 | 5500K | $(1.68, 1.70, 1.66)$ | 8.0 | 现代 E-6 反转片，清澈通透的冷白高光与纯正蓝青还原 | 
| **E-6/K-14 反转片** | `kodachrome_64_k14` | Kodachrome 64 (K-14) | 64 | 5500K | $(1.78, 1.82, 1.75)$ | 10.0 | K-14 外偶联工艺：乳剂不含油溶成色剂液滴，MTF50 高达 92 c/mm，窄带染料赋予极高红/青分离度与厚重暗部 | 
| **黑白银盐负片** | `ilford_hp5_plus_400` | Ilford HP5 Plus 400 | 400 | 5500K | $(0.62, 0.62, 0.62)$ | 14.5 | 经典英伦纪实黑白负片，宽广中间调阶调与高迫冲潜力 | 
| **黑白银盐负片** | `ilford_delta_3200` | Ilford Delta 3200 | 3200 | 5500K | $(0.58, 0.58, 0.58)$ | 24.0 | 核壳结构超高速黑白胶片，强烈有机的粗颗粒微结构 | 
| **黑白银盐负片** | `kodak_trix_400` | Kodak Tri-X 400 (400TX) | 400 | 5500K | $(0.68, 0.68, 0.68)$ | 16.0 | 扎实硬朗的暗部反差与极具辨识度的银盐颗粒结构 | 
| **黑白银盐负片** | `kodak_double_x_5222` | Kodak Double-X (5222) | 250 | 5500K | $(0.65, 0.65, 0.65)$ | 14.0 | 经典黑白电影负片（《辛德勒的名单》《奥本海默》同款黑白底片） | 
| **RA-4 / 电影正片** | `kodak_endura_premier` | Kodak Endura Premier (RA-4) | 2 | 3200K | $(2.42, 2.45, 2.40)$ | 4.0 | 暗房人像/商业扩印标杆相纸，自然温暖的肤色与饱满黑位 | 
| **RA-4 / 电影正片** | `fujifilm_crystal_archive_typeii` | Fujifilm Crystal Archive Type II | 2 | 3200K | $(2.55, 2.58, 2.52)$ | 3.8 | 清爽通透的蓝绿响应与略微陡峭的明快反差 | 
| **RA-4 / 电影正片** | `kodak_vision_2383` | Kodak Vision Color Print 2383 | 3 | 3200K | $(2.85, 2.92, 2.80)$ | 5.0 | 电影工业印片正片黄金标准：$D_{\max} \approx 3.6$，标志性青蓝暗部与金暖高光 | 
| **RA-4 / 电影正片** | `fujicolor_eterna_cp_3513di` | Fujicolor Eterna-CP 3513DI | 3 | 3200K | $(2.72, 2.76, 2.70)$ | 4.8 | 相比 2383 拥有更柔和的阴影趾部与更中性的暗部过渡 | 
| **黑白可变反差相纸** | `ilford_multigrade_fb_classic` | Ilford Multigrade FB Classic | 4 | 3200K | $(2.15, 2.15, 2.15)$ | 3.5 | 钡基光纤可变反差黑白相纸，支持 00 至 5 号暗房反差滤光片无级调节 | 

## 3. iPhone 13 Pro Max 原生 iOS 工程架构与硬件对齐（Milestone 3）

### 3.1 专为 iPhone 13 Pro Max (`iPhone14,3`) 深度定制的硬件对齐策略

1. **A15 Bionic 5 核 GPU 与 6GB LPDDR4X 统一内存零拷贝优化**：

   * 在 `MetalFilmRenderer.swift` 中，通过 `CVMetalTextureCacheCreateTextureFromImage` 将相机输出的 10-bit `kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange` 帧的 Y 平面（`.r16Unorm`）与 CbCr 平面（`.rg16Unorm`）直接映射为 Metal 纹理，实现 **CPU-GPU 零拷贝（Zero-Copy）**。

   * 所有中间物理阶段纹理（`texSceneLinear`、`texLogEncoded`、`texEmulsionExposure`、`texScatteredExposure`、`texNegativeDensity`）均采用 `.rgba16Float` 格式，并统一从单个 `MTLHeap`（`.storageMode = .private`）中分配，显存占用固定可控，杜绝了 4K 30fps 连续录制或 12MP Apple ProRAW 处理时触发 iOS 6GB 内存上限 Jetsam 强杀。

2. **三摄模组光学对齐**：

   * 在 `CameraCaptureService.swift` 中完整封装了 iPhone 13 Pro Max 的三颗后置镜头：13mm $f/2.4$ 超广角（支持 2cm 微距）、26mm $f/1.5$ 广角主摄（$1.9\,\mu\text{m}$ 大像素 + Sensor-Shift 传感器位移防抖）与 77mm $f/2.8$ 3 倍光学长焦，切换镜头时自动同步物理焦距与 $\cos^4\theta$ 暗角模型。

3. **iPhone 13 Pro Max 专属双轨 Log 视频管线**：

   * 鉴于 Apple 官方 `AVCaptureColorSpace.appleLog` 仅向 iPhone 15 Pro 及后续机型开放，本工程在 iPhone 13 Pro Max 上启用硬件 **10-bit BT.2020 HLG** 采集，并在 Metal 首节点 `kernel_ycbcr10_to_scene_linear_and_log` 中通过 ITU-R BT.2100 精确逆向 OETF 与逆系统 Gamma ($\gamma_{\text{sys}} = 1.2$) 还原约 12 档场景线性光（Scene-Linear Rec.2020）。

   * 随后同步分流两条轨道：一路编码为标准对数传递函数（支持 **Apple Log 兼容传递函数**、**ARRI LogC3 (EI 800)** 与 **Kodak Cineon Printing Density Log**），另一路进入 81 波段物理暗房管线。用户可随时切换“纯 Log 底片直录 + 实时物理胶片取景器监看”**或**“物理胶片效果实时 10-bit HEVC / ProRes 422 HQ 烘焙录制”。

## 4. GitHub Actions 双重免压缩构建流水线与自检清单（Milestone 4）

### 4.1 双重免压缩（Zero-Compression）构建工作流机制

在 `.github/workflows/build.yml` 中，构建流水线严格执行以下关键步骤：

1. **无 `.xcodeproj` 二进制污染**：在 `macos-15` Runner 上调用 `xcodegen generate --spec project.yml` 动态生成 Xcode 工程，并提前调用 `xcrun -sdk iphoneos metal` 对 `SpectralPipeline.metal` 进行预编译校验。

2. **免证书编译与 Ad-Hoc 自签**：通过 `CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` 编译 `arm64` Release 包，随后执行 `ldid -S` 与 `codesign --force --deep --sign -`，可直接通过 SideStore、AltStore、Sideloadly 或 TrollStore 安装至 iPhone 13 Pro Max。

3. **双重免压缩保障**：

   * **第一层（IPA 归档免压缩）**：使用 `zip -0 -r -y SpektraCam-Unsigned-Uncompressed.ipa Payload`（`-0` 强制 `store` 仅存储模式，零 Deflate 压缩，保留符号链接）。

   * **第二层（GitHub Actions 产物上传免压缩）**：在 `actions/upload-artifact@v4` 中显式声明 `compression-level: 0`，确保下载产物零二次压缩损耗。

## 5. 参考资料与学术/工程引用索引（Verified Citations）

* Andrea Volpato, [GitHub - andreavolpato/spektrafilm: Spectral simulation of analog photography processes](https://github.com/andreavolpato/spektrafilm)

* Andrea Volpato (`arctic`), [Spectral film simulations from scratch - discuss.pixls.us](https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209)

* Akshay Sharma (`thetechgeekko`), [GitHub - thetechgeekko/Spektrafilm-android: Native C++/NDK & Vulkan Compute port of spektrafilm](https://github.com/thetechgeekko/Spectrafilmandroid)

* Aedan Diez (`chaert-s`), [GitHub - chaert-s/spektrafilm-ofx: Metal/Vulkan OpenFX plugin for DaVinci Resolve](https://github.com/chaert-s/spektrafilm-ofx)

* Lift Gamma Gain Colorist Forum, [Spektrafilm OFX Thread](https://www.liftgammagain.com/forum/index.php?threads/spektrafilm-ofx.19764/) & [xere.my Review of spektrafilm OFX](https://xere.my/davinci-plugins/spektrafilm-ofx/)

* Johannes Hanika (`hanatos`), [vkdt filmsim: arctic's sophisticated spectral analog film simulation](https://jo.dreggn.org/vkdt/src/pipe/modules/filmsim/readme.html)

* Benjamin (`piratenpanda`), [Spektrafilm darktable module implementation discussion - discuss.pixls.us](https://discuss.pixls.us/t/spektrafilm-darktable-module-implementation-discussion/58744)

* Reddit `r/spektrafilm`, [Unspektrawesome: An Android port of the spektrafilm pipeline as a Camera app](https://www.reddit.com/r/spektrafilm/comments/1wdo3e9/unspektrawesome_an_android_port_spektrafilm/)

* LightCraft Project, [GitHub - storytold/lightcraft](https://github.com/storytold/lightcraft) & [Issue #988: Advanced film simulation via spektrafilm](https://github.com/storytold/lightcraft/issues/988)

* Video Village, [Grading with Filmbox · User Guide](https://videovillage.com/learn/filmbox/full-guide/grading-with-filmbox) & [Filmbox Pro Overview](https://videovillage.com/filmbox/buy)

* Dehancer Team, [Dehancer Film Emulation Features (Print Films, Halation, Bloom, Push/Pull, CMY Head)](https://www.dehancer.com/features)

* Cullen Kelly, [Genesis: Digitally Modeled Film Chemistry](https://cullenkellycolor.com/genesis) & [Mixing Light Deep Dive on Genesis Plugin](https://mixinglight.com/color-grading-tutorials/deep-dive-cullen-kelly-genesis-plugin/)

* FilmConvert, [FilmConvert Nitrate Overview](https://www.filmconvert.com/nitrate) & [Nitrate OFX Documentation](https://www.filmconvert.com/tutorials?product=nitrate&software=ofx)

* Wenzel Jakob & Johannes Hanika (2019), [A Low-Dimensional Function Space for Efficient Spectral Upsampling (Eurographics 2019)](https://rgl.epfl.ch/publications/Jakob2019Spectral), [Full Paper PDF](https://jo.dreggn.org/home/2019_sigmoid.pdf) & [GitHub - mitsuba-renderer/rgb2spec](https://github.com/mitsuba-renderer/rgb2spec)

* Ambra Cattaneo (MIPS Lab, University of Milan), [Colour Photographic Processes: Dye Coupler Process](https://mips.di.unimi.it/wp/wp-content/uploads/2022/08/Dye-coupler-print.pdf)

* Peter Bergthaller (2002), [Couplers in colour photography—chemistry and function Part 1 (The Imaging Science Journal, 50:3, 153-186)](https://www.researchgate.net/publication/288740475_Couplers_in_colour_photography-chemistry_and_function_Part_1) & [Part 2](https://www.researchgate.net/publication/289392801_Couplers_in_colour_photography-chemistry_and_function_Part_2)