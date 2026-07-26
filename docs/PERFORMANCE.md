# 性能基线

测量环境：当前 Codex VPS、Docker 29.6.0、Linux x86_64、`myshell:dev`
生产镜像。容器限制为 1 CPU、256 MiB 内存、128 PID；根文件系统只读，全部
capability 已删除。

| 指标 | 目标 | 实测 |
| --- | ---: | ---: |
| `/health` 冷启动 | `< 1 s` | `0.39 s` |
| 空闲 CPU | `< 0.5%` | `0.00%` |
| 容器空闲内存 | `< 50 MiB` | `1.72–2.36 MiB` |
| PID 1 RSS | `< 50 MiB` | `7.47 MiB` |
| 1 个终端容器内存 | `< 10 MiB` 增量 | `2.16 MiB` 总量 |
| 8 个终端容器内存 | `< 10 MiB/终端` | `4.63 MiB` 总量 |
| 文件描述符 | 关闭后恢复 | `7 → 23 → 7` |
| 最终镜像 | 尽量 `< 50 MiB` | `9,347,085 bytes` |
| 服务二进制 | 记录 | `8,044,706 bytes` |

`ps` 检查确认关闭 8 个终端后只剩 PID 1 的 `myshell-server`，没有孤儿 Shell。
Go 运行时会保留少量已创建的 OS 线程，Docker 的 PIDs 统计因此不会立即回到
首次启动值，但进程和文件描述符均已回收。

2026-07-26 追加执行了 25 次真实浏览器 WSS/PT​​Y 创建后直接关闭页面的压力
循环。每轮均在 3 秒内回到 0 个活动会话；完成后 `docker top` 只显示
`myshell-server`，没有残留 Shell。此时空闲 CPU 为 `0.00%`，容器内存为
`7.527 MiB`，PID 1 有 8 个文件描述符。测试由此发现并修复了 WebSocket
断开时 PTY 阻塞读取未被唤醒的问题。

测量命令：

```bash
/usr/bin/time -f '%e s' curl --retry 20 --retry-delay 0 --retry-connrefused \
  http://127.0.0.1:18080/health
docker stats --no-stream myshell-myshell-1
docker image inspect myshell:dev --format '{{.Size}}'
docker exec myshell-myshell-1 sh -c 'ls /proc/1/fd | wc -l'
```

所有结果必须注明 VPS CPU、内存、内核、Docker 版本和测试终端数量。
