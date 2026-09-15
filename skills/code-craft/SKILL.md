---
name: code-craft
description: 写业务代码时的七条判据与 before/after 对照——主路径留在最外层、名字给出业务含义、外部系统止于适配层、类型只描述真实状态、决策与副作用分离、错误同时给 code 与 message、一个变更一个目的。新写函数、重构既有代码、给代码写法做 review 时加载。触发词：写函数、重构、代码规范、嵌套太深、命名、错误处理、这段怎么写。
---

# code-craft — 七条代码写法判据

判断标准贯穿七条：让下一次改动更容易。判断一段代码好不好，不看它这次能不能跑，看别人接手改它时要付出多少。

## 1 · 主路径清晰可见

**判据**：函数的核心操作在最外层缩进；前置条件用 guard 挡在前面，一条不满足就立刻返回。

```ts
// 前：真正要做的事被埋在三层里
if (user) {
  if (user.isActive) {
    if (user.hasPermission) {
      updateProfile(user);
    }
  }
}

// 后：核心操作一眼可见
if (!user) return;
if (!user.isActive) return;
if (!user.hasPermission) return;
updateProfile(user);
```

**为什么**：嵌套一深，代码就成了浆糊。想知道某个操作在什么条件下才执行，得把缩进一层层数回去；反过来想知道某个条件下都做了哪些事，又得辨认哪些语句属于这一层。读的人只能靠 IDE 的自动缩进对齐才还原得出逻辑结构——这份力气本来不必花。

**条件一多就抽成函数**——这和习惯 5 是同一件事。前置条件超过两三条，或这组条件本身有业务含义时，把判定收进一个命名函数，主路径只留一句 guard：

```ts
function canUpdateProfile(user: User | null): user is User {
  return !!user && user.isActive && user.hasPermission;
}

if (!canUpdateProfile(user)) return;
updateProfile(user);
```

主路径缩到两行，条件的业务含义落在函数名上，判定本身也可以脱离 `updateProfile` 单独测。

---

## 2 · 名字带业务含义

**判据**：变量名回答"这是什么"，函数名回答"接下来发生什么"。业务含义具体时，不用 `data` / `result` / `item` / `info` / `handle`。

```ts
// 前：得翻到别处才知道 data 是什么
const data = getData(id);
if (data.status === "PENDING") process(data);

// 后：名字自己说清了
const pendingOrder = await getOrder(orderId);
if (pendingOrder.status === "PENDING") await processOrder(pendingOrder);
```

**边界**：不必给所有东西起长名字。循环里的 `i`、一行内即用即弃的中间量保持短；重要概念才值得长名字。

---

## 3 · 外部系统隔离在边界

**判据**：第三方的字段名、错误格式、枚举值只出现在适配层。应用内部只见自己的领域名字。

```ts
// 前：supabase / 支付方的字段名渗进业务逻辑，对方改字段就得全仓库搜
const res = await paymentService.getUser(id);
if (res.customer_status === "active") enableFeature(res.customer_name);

// 后：在边界转一次，改动收敛到一个函数
function toCustomer(res: PaymentApiUser): Customer {
  return { name: res.customer_name, isActive: res.customer_status === "active" };
}
const customer = toCustomer(await paymentService.getUser(id));
if (customer.isActive) enableFeature(customer.name);
```

**边界**：一次性脚本、只用一处的内部接口，直接用原字段即可。

---

## 4 · 让无效状态难以表示

**判据**：类型只描述真实存在的状态。把"这里一定有值"写进类型，而不是每处用前再判一次。

```ts
// 前：全 optional，于是应用每一处都要重问一遍"存在吗 / 有效吗"
type Order = { id?: string; status?: string; paymentId?: string };

// 后：类型本身表达"已支付订单，这些值一定在"
type PaidOrder = { id: string; status: "paid"; paymentId: string };
type Order = { id: string; status: "draft" } | PaidOrder;
```

```python
# Python 侧同理：用 Literal + 必填字段替代满屏 Optional
class PaidOrder(BaseModel):
    id: str
    status: Literal["paid"]
    payment_id: str
```

**边界**：消灭不了所有错误状态，目标是让错误状态更难被构造出来。

---

## 5 · 决策与动作分离

**判据**：业务规则算成一个值，副作用另起一段执行。规则本身不碰数据库、网络、文件。

```ts
// 前：规则和写库、发信绞在一起，想测规则就得连数据库
if (user.age >= 18 && user.isVerified) {
  await database.enableFeature(user.id);
  await sendEmail(user.email);
}

// 后：判定是纯函数，可单独测；副作用留在调用处
function canUseFeature(user: User): boolean {
  return user.age >= 18 && user.isVerified;
}
if (canUseFeature(user)) {
  await database.enableFeature(user.id);
  await sendEmail(user.email);
}
```

**适用面**：权限、计费、判分、校验、重试、通知——这几类正是本机测试义务表里"必测"的部分，分离后它们才测得动。

---

## 6 · 错误对人和机器都可用

**判据**：错误响应同时给出机器读的 `code` 和人读的 `message`。日志带排查上下文，且不含任何凭据。

```jsonc
// 前：调用方无法据此做任何分支
{ "message": "Something went wrong" }

// 后：code 给系统判分支，message 给人看
{ "code": "EMAIL_ALREADY_EXISTS", "message": "该邮箱已注册" }
```

日志记 request id、endpoint、时间戳、error code。password、token、secret、完整请求体一律不进日志。

---

## 7 · 一个变更一个目的

**判据**：一个 PR 只服务一个目的。新功能、重构、schema 变更、前端改版、重试逻辑各自成 PR。

```
# 前：能跑，但没法 review，出事没法单独回滚
PR: Update checkout
  + 新增结算功能  + 重构支付服务  + 改数据库  + 改前端  + 改重试逻辑

# 后：每个都能独立 review、测试、回滚
PR 1 → 新增结算校验
PR 2 → 重构支付服务
PR 3 → 更新结算页 UI
```

**理由**：软件变难不在写第一版，而在于之后第 50 次改动比它本该的样子更难。

---

## 贯穿七条的那一条

**让下一次改动更容易。** 判断一段代码好不好，不看它这次能不能跑，看别人接手改它时要付出多少。
