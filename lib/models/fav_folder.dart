// lib/models/fav_folder.dart
class FavFolder {
  final String id;
  String name;
  String? avatarPath;
  final List<String> chatIds; // ordered, mutable

  FavFolder({
    required this.id,
    required this.name,
    this.avatarPath,
    List<String>? chatIds,
  }) : chatIds = chatIds ?? [];

  factory FavFolder.create(String name) => FavFolder(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: name,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (avatarPath != null) 'avatarPath': avatarPath,
        'chatIds': chatIds,
      };

  factory FavFolder.fromJson(Map<String, dynamic> json) => FavFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        avatarPath: json['avatarPath'] as String?,
        chatIds: (json['chatIds'] as List?)?.cast<String>().toList() ?? [],
      );
}
