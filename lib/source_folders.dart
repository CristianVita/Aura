import 'app_strings.dart';

import 'package:flutter/material.dart';

class SourceFolderSelection {
  SourceFolderSelection(Set<String>? folders)
    : folders = folders == null ? null : Set.unmodifiable(folders);
  final Set<String>? folders;
}

class SourceFoldersScreen extends StatefulWidget {
  const SourceFoldersScreen({
    super.key,
    required this.folderCounts,
    required this.selectedFolders,
  });
  final Map<String, int> folderCounts;
  final Set<String>? selectedFolders;

  @override
  State<SourceFoldersScreen> createState() => _SourceFoldersScreenState();
}

class _SourceFoldersScreenState extends State<SourceFoldersScreen> {
  late bool _allFolders;
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _allFolders = widget.selectedFolders == null;
    _selected = {...?widget.selectedFolders};
  }

  @override
  Widget build(BuildContext context) {
    final folders = widget.folderCounts.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final count = widget.folderCounts.entries
        .where((entry) => _allFolders || _selected.contains(entry.key))
        .fold<int>(0, (sum, entry) => sum + entry.value);
    return Scaffold(
      appBar: AppBar(title: Text(context.appStrings.uiMusicFolders)),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: Text(
              context.appStrings.uiChooseMusicFoldersOnlyFoldersWhereThe,
            ),
          ),
          SwitchListTile(
            title: Text(context.appStrings.uiAllFolders),
            subtitle: Text(
              context
                  .appStrings
                  .uiAutomaticallyIncludesFoldersFoundInFutureScans,
            ),
            value: _allFolders,
            onChanged: (value) => setState(() => _allFolders = value),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: folders.length,
              itemBuilder: (context, index) {
                final folder = folders[index];
                final total = widget.folderCounts[folder]!;
                return CheckboxListTile(
                  secondary: const Icon(Icons.folder_rounded),
                  title: Text(
                    folder.isEmpty
                        ? context.appStrings.uiUnknownFolder
                        : folder,
                  ),
                  subtitle: Text(
                    total == 0
                        ? context.appStrings.uiNoTracksFoundInTheLastScan
                        : context.appStrings.groupTracks(total),
                  ),
                  value: _allFolders || _selected.contains(folder),
                  onChanged: _allFolders
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(folder);
                          } else {
                            _selected.remove(folder);
                          }
                        }),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.appStrings.tracksInSelection(count),
                    textAlign: TextAlign.center,
                  ),
                  if (!_allFolders && _selected.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        context.appStrings.uiYourLibraryWillStayEmptyUntilYou,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      SourceFolderSelection(_allFolders ? null : _selected),
                    ),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(context.appStrings.uiSaveSelection),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
