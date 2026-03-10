# Local Search Module

局部搜索模块，包含以下算子：

- `two_opt_within_routes_rs.m` - 2-opt 局部搜索（路径内边交换）
- `or_opt_within_routes_rs.m` - Or-opt 局部搜索（客户重插入）
- `relocate_longest_ev_to_cv.m` - 将最长EV路径中的客户迁移到CV
- `try_empty_ev_route.m` - 尝试清空EV路径以减少启动成本
- `greedy_insert_customer.m` - 贪婪插入客户到最优位置

所有函数接受 `G` 作为参数，不使用 `global G`。
