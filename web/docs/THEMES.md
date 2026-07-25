# 内置主题规范

## 1. 主题机制

主题使用 CSS 自定义属性实现。所有组件只能引用语义令牌，禁止在组件内部写死
主题颜色。

```css
:root {
  --color-bg: ...;
  --color-surface: ...;
  --color-elevated: ...;
  --color-border: ...;
  --color-text: ...;
  --color-muted: ...;
  --color-accent: ...;
  --color-success: ...;
  --color-warning: ...;
  --color-danger: ...;
  --color-selection: ...;
  --syntax-comment: ...;
  --syntax-keyword: ...;
  --syntax-string: ...;
  --syntax-number: ...;
  --syntax-function: ...;
  --syntax-property: ...;
}
```

终端、代码预览、导航和表单共享语义色，但终端 ANSI 16 色表单独定义。主题选择
立即预览，保存后进入非秘密设置同步。首次访问默认使用“午夜石墨”；用户可选择
跟随系统。

## 2. 午夜石墨（默认）

| 令牌 | 颜色 |
| --- | --- |
| background | `#0B1117` |
| surface | `#111923` |
| elevated | `#17212B` |
| border | `#2A3642` |
| text | `#E7EDF3` |
| muted | `#93A1AE` |
| accent | `#23BCEB` |
| success | `#58D68D` |
| warning | `#F2B84B` |
| danger | `#FF6B6B` |
| selection | `#16445A` |

语法色：注释 `#7F8C98`、关键字 `#56B6F7`、字符串 `#8FD36A`、数字
`#C792EA`、函数 `#F2C66D`、属性 `#F06C75`。

## 3. 纸白

| 令牌 | 颜色 |
| --- | --- |
| background | `#FFFFFF` |
| surface | `#F5F7F9` |
| elevated | `#FFFFFF` |
| border | `#D7DEE5` |
| text | `#18212B` |
| muted | `#667483` |
| accent | `#087EA4` |
| success | `#248A52` |
| warning | `#A86600` |
| danger | `#C73E45` |
| selection | `#DCEFF7` |

语法色：注释 `#71808F`、关键字 `#005CC5`、字符串 `#22863A`、数字
`#6F42C1`、函数 `#9A6700`、属性 `#B31D28`。

## 4. Solarized Dark

| 令牌 | 颜色 |
| --- | --- |
| background | `#002B36` |
| surface | `#073642` |
| elevated | `#0B414D` |
| border | `#33535B` |
| text | `#EEE8D5` |
| muted | `#93A1A1` |
| accent | `#2AA198` |
| success | `#859900` |
| warning | `#B58900` |
| danger | `#DC322F` |
| selection | `#164E59` |

语法色：注释 `#657B83`、关键字 `#268BD2`、字符串 `#859900`、数字
`#6C71C4`、函数 `#B58900`、属性 `#CB4B16`。

## 5. Nord

| 令牌 | 颜色 |
| --- | --- |
| background | `#2E3440` |
| surface | `#3B4252` |
| elevated | `#434C5E` |
| border | `#4C566A` |
| text | `#ECEFF4` |
| muted | `#D8DEE9` |
| accent | `#88C0D0` |
| success | `#A3BE8C` |
| warning | `#EBCB8B` |
| danger | `#BF616A` |
| selection | `#4C566A` |

语法色：注释 `#7F8C9D`、关键字 `#81A1C1`、字符串 `#A3BE8C`、数字
`#B48EAD`、函数 `#EBCB8B`、属性 `#D08770`。

## 6. 高对比度

| 令牌 | 颜色 |
| --- | --- |
| background | `#000000` |
| surface | `#080808` |
| elevated | `#101010` |
| border | `#FFFFFF` |
| text | `#FFFFFF` |
| muted | `#D6D6D6` |
| accent | `#00FFFF` |
| success | `#5CFF5C` |
| warning | `#FFFF00` |
| danger | `#FF5C5C` |
| selection | `#004C66` |

语法色：注释 `#C8C8C8`、关键字 `#00FFFF`、字符串 `#5CFF5C`、数字
`#FF8CFF`、函数 `#FFFF00`、属性 `#FF7A7A`。

## 7. 验收要求

- 普通文字与背景至少达到 WCAG AA。
- 高对比主题优先达到 AAA。
- 焦点、选择、错误和状态不能只靠颜色区分。
- 切换主题不得重建或丢失终端会话。
- 主题变量必须同时更新 UI、终端 ANSI 色和代码高亮。
- 主题偏好损坏时安全回退到午夜石墨。
