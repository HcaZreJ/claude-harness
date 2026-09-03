# 信息层级设计原则调研存档（2026-07-22）

> SKILL.md 是本文的蒸馏层。本文是完整调研：17 条原则（每条含陈述/依据出处/违反症状/检查方法）、单页自检清单原稿、全部信源。原则适用于任何界面与版面。

## 一、原则清单（17 条，按六个方向分组）

### A. 视觉层级基本原理

**A1. 大小/字重优先编码重要度**
- ①陈述：一屏内最重要的信息（标题/核心结论）应是尺寸最大或字重最重的元素，次要信息依次递减，整屏字阶不超过 2-3 级。
- ②依据：NN/G《5 Principles of Visual Design in UX》——"using relative size to signal importance and rank"；IxDF《Visual Hierarchy》建议限制字体数量（通常 2-3 种）。
- ③违反症状：页面所有文字"一样重"，用户读完说不出哪句是核心；或免责声明字号和标题一样大。
- ④检查方法：看截图 0.5 秒后立刻问"记住了哪个词"，答案应与设计意图一致；数字号级数，超过 3 级需说明理由。

**A2. 邻近性编码从属关系（Gestalt Proximity）**
- ①陈述：同组元素间距应明显小于不同组元素间距，间距本身就是"这是一伙的"的语言。
- ②依据：NN/G《Proximity Principle in Visual Design》——邻近性"can overpower competing visual cues such as similarity of color or shape"；用户漏点按钮常因它离相关内容太远。
- ③违反症状：标签与所属卡片的间距等于它到无关卡片的间距，归属被误读。
- ④检查方法：组间距应至少是组内距的 1.5-2 倍；把色块蒙成同色只留边框，分组关系应仍能靠间距辨认。

**A3. 留白是主动的强调手段，不是剩余空间**
- ①陈述：围绕重要内容的留白越充分，其被感知的重要度越高；留白同时降低认知负荷。
- ②依据：IxDF 八要素列表把留白列为独立层级编码手段；NN/G 视觉设计原则同。
- ③违反症状：卡片贴在一起，找不到扫视呼吸点，也判断不出谁更重要。
- ④检查方法：留白面积占比低于 30% 属拥挤；最重要元素周围应有刻意更大的空白圈。

**A4. 移动端线性/F 型扫视，关键信息前置**
- ①陈述：竖屏下用户从上到下线性扫视，句首/屏顶承载最多注意力，结论性信息放最前。
- ②依据：NN/G《F-Shaped Pattern of Reading Web Content》眼动研究——F 型扫视在桌面与移动端都成立，"place information-bearing words at the beginning of headings"；移动端竖向滚动下线性/Z 型更普遍。
- ③违反症状：核心结论埋在段落中间或卡片最后一行。
- ④检查方法：只读每屏顶部 1/3 和每段第一句，能否拼出本页完整意思。

### B. 强调色使用纪律

**B1. 一屏一个视觉焦点（60-30-10 法则）**
- ①陈述：每屏应有且只有一个"最亮眼"元素（通常是主 CTA），其余视觉强度明显低于它。
- ②依据：60-30-10 配色法则（hype4.academy）——60% 主色/30% 辅色/10% 强调色；"如果所有颜色都同样鲜艳，整个空间看起来混乱、无序"。
- ③违反症状：两个同样鲜艳的按钮/色块打架，用户不知先点哪个。
- ④检查方法：转灰度或眯眼，只有一处元素脱颖而出；数高饱和色块，正常 1 个（最多 2：CTA + 当前状态）。

**B2. 强调色语义单一化，不可一色多义**
- ①陈述：强调色在整个体系内只对应一种语义（如"可点击的下一步"），此页表"正确"、彼页表"警示"或纯装饰即违反。
- ②依据：Nielsen 可用性启发式第 4 条 Consistency and Standards——"users should not have to wonder whether different words, situations, or actions mean the same thing"。
- ③违反症状：同一强调色 A 页可点、B 页装饰；用户误点或漏点。
- ④检查方法：列出全部强调色用例逐一标注语义，同色对应两种以上互不兼容语义即违反。

**B3. 红色专属警示/错误语义，不作装饰**
- ①陈述：红色专指错误/危险/删除等负面信息；"重点内容"用主强调色。
- ②依据：UX Planet《Using Red and Green in UI Design》——red 用于 destructive elements、errors、critical messages；"never using color as the sole indicator"——每个错误需图标 + 文字并行（色弱兜底）。
- ③违反症状：红色高亮"划重点"（用户误读为警告，产生焦虑）；纯色无图标文字。
- ④检查方法：搜出全部红色元素，逐个确认属于错误/警示/危险/删除四类之一。

### C. 并列结构的语义

**C1. 同款卡片并排 = 同级信息，非同级不可并列**
- ①陈述：视觉相同的卡片并排传达"平行、同重要度、可任意顺序读"；内容存在时间先后、因果递进或主次从属时，改用序号/时间轴/主卡+子卡结构。
- ②依据：NN/G《Cards: UI-Component Definition》——卡片适合异质内容浏览，不适合需要顺序或比较的场景；Gestalt 相似性——共享形状/颜色/字体的元素被自动归为一组。
- ③违反症状：三张一模一样的卡片讲"第一步、第二步、第三步"，用户以为可任选。
- ④检查方法：圈出同款重复卡片，问"它们之间是否存在顺序/主次/因果"——有则需引入序号、箭头、字号差或渐强配色打破同级信号。

**C2. 出现逻辑先后时改用递进/从属结构**
- ①陈述："先决条件→结果""原理→应用""反例→正例"用序号、箭头、阶梯缩进或渐强色阶替代平铺卡片，让结构本身读出顺序。
- ②依据：C1 的推论 + NN/G 位置/重复编码手段——位置先后本身是层级信号。
- ③违反症状：先反例后正例的一页用完全对称的左右卡片，无先后线索。
- ④检查方法：打乱两块内容的阅读顺序会影响理解，但视觉上无顺序提示 → 改结构。

### D. 每个视觉差异必须编码一个信息差异

**D1. 视觉差异必须对应真实信息差异（Tufte data-ink / chartjunk 迁移）**
- ①陈述：任何颜色、粗细、阴影、装饰图形的差异都必须对应真实的信息或状态差异。
- ②依据：Tufte《The Visual Display of Quantitative Information》(1983) data-ink ratio；chartjunk = "ink that does not tell the viewer anything new"；"smallest effective difference"——"make all visual distinctions as subtle as possible, but still clear and effective"。"When everything is emphasized, nothing is emphasized"广泛归于 Tufte 的设计哲学（二手文献常见，未定位到原书页码，引用时标注"广泛归于 Tufte"）。
- ③违反症状：卡片加阴影/渐变/图标只为"精致"，重要度不同的相邻卡片用同样重的装饰，噪音掩盖真实差异。
- ④检查方法：列出全部"视觉变化点"逐一反问"对应哪个信息差异？"——答不出即 chartjunk，删或降为中性样式。

**D2. 设计一致性：同一含义只用同一样式，同一样式只对应同一含义**
- ①陈述：某样式（如"浅绿底+对勾"）一旦定义为某含义（"已完成"），全部页面严格复用。
- ②依据：Nielsen 启发式第 4 条，D1 在跨页尺度上的延伸。
- ③违反症状：同一图标 A 处表"已选中"、B 处表"已完成"；进度条填充色一会绿一会蓝。
- ④检查方法：建"样式→含义"映射表，扫多页核查一对多/多对一映射。

### E. 排版层级实践

**E1. 单页字阶克制在 2-3 级**
- ①陈述：单屏字号层级 ≤2-3 级（标题/正文/辅助小字）。
- ②依据：IxDF 建议通常 2-3 种；NN/G 建议不超过 3 种尺寸。
- ③违反症状：同屏 5 种字号，分不清标题/次级标题/加粗正文。
- ④检查方法：量出全部字号值去重计数，超 3 种合并相邻字阶。

**E2. Eyebrow/overline 只标注类别归属，不可喧宾夺主**
- ①陈述：标题上方的小字标签只承载"本页属于哪个环节/系列"的元信息，1-5 词，样式明显弱于主标题；非每屏必配。
- ②依据：Verdigris Design System / Socialectric——"should never be styled so prominently that it overshadows the heading"；"If every section has one, the pattern loses its navigational value"。
- ③违反症状：eyebrow 字号/颜色接近主标题；每屏都堆一个，用户逐渐无视。
- ④检查方法：eyebrow 与主标题的字号/字重/饱和度三项都应明显更弱。

**E3. 离散并列用 bullet，因果叙事用整句**
- ①陈述：3 条以上互相独立、可打乱顺序的要点用 bullet（格式对称、每条 1-2 行）；依赖"因为/所以/但是"推进的内容保留整句/短段落。
- ②依据：NN/G《7 Tips for Presenting Bulleted Lists》——三项以上才用列表、每条不超两三行、同列表并列结构对称。
- ③违反症状：有因果关系的说理被生硬拆成三条 bullet，逻辑关系丢失；或该 bullet 的并列要点写成密集大段。
- ④检查方法：删掉条目间连接词后语义仍完整独立 → 适合 bullet；断裂 → 改整句。

### F. 分页节奏与认知负荷

**F1. 单屏单知识点（one screen, one idea）**
- ①陈述：每屏只承担一个目标/概念。
- ②依据：微学习文献——"the cardinal rule of microlearning is one module, one idea"；多概念同屏导致认知过载、留存下降。
- ③违反症状：一屏既讲"什么是提示词"又讲"三个优化技巧"，读完什么都没记住。
- ④检查方法：一句话总结本屏唯一该记住的事；需要"和"连接两件不相关的事 → 拆屏。

**F2. 并列选项数量控制在工作记忆容量内**
- ①陈述：一屏并列选项/要点 3-4 个为佳，上限勿超 5-7；超容量则分屏或合并为更高层组块。
- ②依据：Miller (1956) 7±2；**Cowan (2001) 修正：排除复述和组块策略后，现实工作记忆容量更接近 4 个组块**——比笼统的 7±2 更严格、更符合最新认知科学。
- ③违反症状：一屏 6 张并列选择卡来回滚动比较，决策疲劳。
- ④检查方法：数同级并列元素，超 4 个检查可否合并为 2-3 个更抽象组块。

**F3. 短内容分段 + 可视化进度节奏**
- ①陈述：一次专注周期内可完成（短课实践 3-10 分钟/节），持续展示"我在哪、还剩多少"。
- ②依据：Duolingo bite-sized lessons（5-10 分钟）+ spaced repetition；Headspace 3-5 分钟单主题冥想。
- ③违反症状：20+ 屏无进度提示，用户不知还要点多少次"下一步"，中途流失。
- ④检查方法：总屏数 × 每屏时长超 5-8 分钟且无进度可视化 → 拆分或补进度。

## 二、单页自检清单（评审一页截图时的操作顺序）

1. **焦点测试**（B1）：眯眼/转灰度，是否只有一处明显脱颖而出？
2. **0.5 秒记忆测试**（A1/A4）：闪一眼截图，记住的东西与设计意图一致吗？
3. **单一知识点测试**（F1）：能否一句话概括本屏唯一内容？
4. **并列元素计数**（F2）：同级并列个数 ≤4？
5. **同级性检验**（C1/C2）：长得一样的卡片之间，有没有被并列样式掩盖的顺序/主次？
6. **强调色语义核查**（B2）：本屏强调色的语义与其它页一致吗？
7. **红色使用核查**（B3）：红色是否都属错误/警示/危险/删除，且配图标+文字？
8. **字阶计数**（E1）：≤3 种字号？
9. **Eyebrow 核查**（E2）：字号/颜色明显弱于主标题？
10. **Bullet vs 整句**（E3）：列表条目可打乱顺序？因果叙事保留整句？
11. **视觉差异溯源**（D1）：每处装饰性变化都能说出对应的信息差异？
12. **跨页一致性抽查**（D2）：本屏样式含义与其它页零冲突？
13. **邻近/留白检查**（A2/A3）：组内/组间间距比清晰？留白 ≥30%？
14. **节奏检查**（F3）：总屏数与进度提示匹配预期时长？

## 三、信源列表

| 来源 | 说明 |
|---|---|
| [NN/G – 5 Principles of Visual Design in UX](https://www.nngroup.com/articles/principles-visual-design/) | 大小/颜色/对比/间距编码重要度 |
| [NN/G – F-Shaped Pattern of Reading Web Content](https://www.nngroup.com/articles/f-shaped-pattern-reading-web-content/) | 眼动研究：F 型扫视移动端依然成立 |
| [NN/G – Cards: UI-Component Definition](https://www.nngroup.com/articles/cards-component/) | 卡片组件适用场景与并列语义 |
| [NN/G – Proximity Principle in Visual Design](https://www.nngroup.com/articles/gestalt-proximity/) | Gestalt 邻近性 |
| [NN/G – Consistency and Standards](https://www.nngroup.com/articles/consistency-and-standards/) | 同一含义同一样式 |
| [NN/G – 7 Tips for Presenting Bulleted Lists](https://www.nngroup.com/articles/presenting-bulleted-lists/) | bullet 使用规范 |
| [IxDF – What is Visual Hierarchy?](https://ixdf.org/literature/topics/visual-hierarchy) | 八要素综述 |
| [Hype4 Academy – 60-30-10 Colors in UI Design](https://hype4.academy/articles/design/60-30-10-rule-in-ui) | 强调色配色与单一焦点 |
| [UX Planet – Using Red and Green in UI Design](https://uxplanet.org/using-red-and-green-in-ui-design-66b39e13de91) | 红色警示语义与滥用风险 |
| [Medium – The Smallest Effective Difference](https://medium.com/@pj_/the-smallest-effective-difference-90fc94d5ab0d) | Tufte 最小有效差异 |
| [GeeksforGeeks – Tufte's Data Visualization Principles](https://www.geeksforgeeks.org/data-visualization/mastering-tuftes-data-visualization-principles/) | chartjunk/data-ink 综述 |
| [InfoVis Wiki – Data-Ink Ratio](https://infovis-wiki.net/wiki/Data-Ink_Ratio) | data-ink 定义 |
| [Verdigris Design System – Eyebrow Typography](https://design.verdigris.co/categories/typography/eyebrow) | eyebrow 规范 |
| [Socialectric – Eyebrow Text in Web Design](https://www.socialectric.com/insights/eyebrow-text-web-design) | eyebrow 层级克制 |
| [Attention Insight – Similarity in Design](https://attentioninsight.com/similarity-in-design-visual-relationships/) | 相似性与并列卡片语义 |
| [Userbrain – Miller's Law](https://www.userbrain.com/blog/millers-law-important-rule-ux-design-everyone-breaks/) | Miller 定律与 Cowan 修正 |
| [Laws of UX – Miller's Law](https://lawsofux.com/millers-law/) | 7±2 出处与应用 |
| [OttoLearn – Microlearning Reduces Cognitive Load](https://www.ottolearn.com/post/119-seven-ways-microlearning-helps-you-reduce-cognitive-load) | 认知负荷与微学习 |
| [SC Training – Microlearning Design Model](https://training.safetyculture.com/blog/microlearning-design-model/) | "one module, one idea" |
| [Omniplex Learning – Designing Microlearning](https://omniplexlearning.com/insights/blog/designing-microlearning/) | 微学习六原则 |

## 四、引用注意事项

1. **"When everything is emphasized, nothing is emphasized" 未核实到 Tufte 原书精确页码**——二手文献广泛归于 Tufte（其 chartjunk / data-ink 体系的通俗化表述），引用时标"广泛归于 Tufte"，勿标精确页码。
2. **Cowan (2001) 对 7±2 的修正（现实容量约 4 组块）**是有价值的精细化：给"并列 ≤4"这个具体数字，比笼统"7±2"更严格且更符合最新认知科学结论。
3. "一屏一个教学目标"这条在微学习国际文献（"one module, one idea"）中有独立依据，不依赖任何单一产品案例。
