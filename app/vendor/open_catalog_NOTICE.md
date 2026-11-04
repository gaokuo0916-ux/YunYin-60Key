# Wikimedia Commons MIDI 目录

本应用新增目录来自 Wikimedia Commons 公共 API 的 `filemime:audio/midi` 查询。本地仅打包文件元数据，选择曲目后从 Commons 原始地址下载。

每份条目保存：曲名、作者/贡献者、原始文件页面、下载地址、文件 SHA-1、许可名称及许可链接。本版纳入 Public Domain、CC0、CC BY 和 CC BY-SA 等明确许可的条目，按原始文件 SHA-1 去重。同一作品的不同转录仍可能作为不同版本列出。

来源：https://commons.wikimedia.org/ 。各文件的具体作者、许可和条件以其原始文件页面为准。目录数量及获取记录见 `open_catalog_source.json`；不将文件数称为不同歌曲数，不保证所有 MIDI 都可直接转成七键单旋律。下载后需选择声部并校对。
