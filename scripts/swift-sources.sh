# 由仓库根目录中的 zsh 构建／本地检查入口 source。
# zsh ** 递归收集，避免新增、删除或移动文件后维护多套清单。
swift_sources=(Sources/BailongPet/**/*.swift(N))
swift_library_sources=(${swift_sources:#*/main.swift})
