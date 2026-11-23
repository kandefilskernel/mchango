import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../api/purchases_api.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';

/// Photos de la marchandise, en grand, à faire défiler du doigt.
class OfferPhotos extends StatefulWidget {
  const OfferPhotos({super.key, required this.paths});

  /// Adresses relatives à l'API (`/offers/<id>/photos/<n>`).
  final List<String> paths;

  @override
  State<OfferPhotos> createState() => _OfferPhotosState();
}

class _OfferPhotosState extends State<OfferPhotos> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final base = Services.of(context).client.baseUrl;
    return Column(
      key: const Key('offer_photos'),
      children: [
        SizedBox(
          height: 240,
          child: PageView.builder(
            itemCount: widget.paths.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.network(
                  '$base${widget.paths[i]}',
                  fit: BoxFit.cover,
                  semanticLabel: t('Photo {n} de la marchandise', {'n': i + 1}),
                  errorBuilder: (_, _, _) => Container(
                    color: Brand.neutral,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_not_supported_outlined, size: 48, color: Colors.grey),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.paths.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.paths.length; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _index ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? Brand.green : Brand.green.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// La discussion sous une offre : chacun pose ses questions, la boutique répond en son nom.
class OfferDiscussion extends StatefulWidget {
  const OfferDiscussion({super.key, required this.offerId});

  final String offerId;

  @override
  State<OfferDiscussion> createState() => _OfferDiscussionState();
}

class _OfferDiscussionState extends State<OfferDiscussion> {
  final _text = TextEditingController();
  int _version = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if (body.isEmpty) return;
    await Services.of(context).purchases.postOfferMessage(widget.offerId, body);
    _text.clear();
    if (mounted) setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) => Padding(
    key: const Key('offer_discussion'),
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.forum_outlined, color: Brand.green),
            const SizedBox(width: 8),
            Text(t('Questions et discussion'), style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          t('Posez vos questions sur la marchandise. La boutique répond ici, tout le monde voit.'),
          style: TextStyle(color: Brand.muted),
        ),
        const SizedBox(height: 10),
        Loader<List<OfferMessage>>(
          key: ValueKey(_version),
          load: () => Services.of(context).purchases.offerMessages(widget.offerId),
          builder: (context, messages, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (messages.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(t('Pas encore de message. Soyez la première personne à demander !'), style: TextStyle(color: Brand.muted)),
                ),
              for (final m in messages) _Bubble(message: m),
            ],
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('offer_message'),
          controller: _text,
          maxLength: 500,
          minLines: 1,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: t('Votre question…'), counterText: ''),
        ),
        const SizedBox(height: 8),
        BusyButton(key: const Key('send_offer_message'), label: t('Envoyer'), icon: Icons.send, onPressed: _send),
      ],
    ),
  );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final OfferMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final (bg, align) = m.fromMerchant
        ? (Brand.goldLight, CrossAxisAlignment.start)
        : m.mine
        ? (Brand.mint, CrossAxisAlignment.end)
        : (Colors.white, CrossAxisAlignment.start);
    return Column(
      crossAxisAlignment: align,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: const BoxConstraints(maxWidth: 320),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Brand.ink.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (m.fromMerchant) ...[const Icon(Icons.storefront, size: 16, color: Brand.goldDark), const SizedBox(width: 4)],
                  Flexible(
                    child: Text(
                      m.mine ? t('Vous') : m.authorName,
                      style: TextStyle(fontWeight: FontWeight.w800, color: m.fromMerchant ? Brand.goldDark : Brand.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(m.body, style: const TextStyle(fontSize: 16, height: 1.35)),
              const SizedBox(height: 2),
              Text(formatDateTime(m.createdAt), style: TextStyle(color: Brand.muted, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une photo choisie par la boutique, prête à envoyer.
class PickedPhoto {
  PickedPhoto(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}

/// Choisir jusqu'à 4 photos de la marchandise, réduites pour rester légères (data chère).
class OfferPhotoPicker extends StatelessWidget {
  const OfferPhotoPicker({super.key, required this.photos, required this.onChanged});

  final List<PickedPhoto> photos;
  final ValueChanged<List<PickedPhoto>> onChanged;

  Future<void> _add(BuildContext context, ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 70);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > 600000) {
      if (context.mounted) showInfo(context, t('Photo trop lourde : 600 Ko au plus. Réduisez-la avant de l’envoyer.'));
      return;
    }
    final name = file.name.toLowerCase();
    final type = name.endsWith('.png') ? 'image/png' : name.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
    onChanged([...photos, PickedPhoto(bytes, type)]);
  }

  @override
  Widget build(BuildContext context) => Column(
    key: const Key('offer_photo_picker'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(t('Photos de la marchandise'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(t('Jusqu’à 4 photos. Les acheteurs voient ce qu’ils achètent.'), style: TextStyle(color: Brand.muted)),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (i, p) in photos.indexed)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(p.bytes, width: 84, height: 84, fit: BoxFit.cover),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  child: IconButton.filledTonal(
                    tooltip: t('Retirer'),
                    iconSize: 18,
                    icon: const Icon(Icons.close),
                    onPressed: () => onChanged([...photos]..removeAt(i)),
                  ),
                ),
              ],
            ),
        ],
      ),
      if (photos.length < 4) ...[
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('photo_camera'),
                onPressed: () => _add(context, ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(t('Prendre')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('photo_gallery'),
                onPressed: () => _add(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(t('Choisir')),
              ),
            ),
          ],
        ),
      ],
    ],
  );
}
