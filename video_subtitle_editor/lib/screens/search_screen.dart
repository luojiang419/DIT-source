import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('查找视频'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              enabled: false,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: '输入字幕关键词进行检索（下一阶段实现）',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Card(
                child: Center(
                  child: Text(
                    '搜索结果列表（下一阶段：双行展示 + 复制路径/打开文件夹 + 双击跳转）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

