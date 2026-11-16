import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nomina_store.dart';
import '../utils/constants.dart';
import '../utils/theme_colors.dart';
import '../widgets/app_drawer.dart';
import '../widgets/screen_status_bar.dart';
import '../widgets/section_app_bar.dart';

class PersonalScreen extends StatefulWidget {
  const PersonalScreen({super.key});

  @override
  State<PersonalScreen> createState() => _PersonalScreenState();
}

class _PersonalScreenState extends State<PersonalScreen> {
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<NominaStore>();
    final q = _buscar.text.trim().toLowerCase();
    final lista = q.isEmpty
        ? store.personas
        : store.personas
            .where((p) =>
                p.dni.contains(q) ||
                p.nombre.toLowerCase().contains(q))
            .toList();
    return ScreenStatusBar(
      color: context.scaffoldMuted,
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: const SectionAppBar(
          title: AppStrings.menuPersonal,
          sectionIcon: Icons.people_rounded,
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: TextField(
                controller: _buscar,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: context.textThemePrimary,
                ),
                decoration: const InputDecoration(
                  hintText: 'Buscar',
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Row(
                children: [
                  Text(
                    '${lista.length}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    ' personas',
                    style: TextStyle(
                      color: context.textThemeSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: lista.isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.people_rounded,
                        size: 72,
                        color: AppColors.textMuted,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      itemCount: lista.length,
                      itemBuilder: (_, i) => _fila(context, lista[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, PersonaFace p) {
    Uint8List? foto;
    if (p.miniatura.isNotEmpty) {
      try {
        foto = base64Decode(p.miniatura);
      } catch (_) {
        foto = null;
      }
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceCard,
        borderRadius: BorderRadius.circular(AppColors.radiusMd),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.surface,
            backgroundImage: foto != null ? MemoryImage(foto) : null,
            child: foto == null
                ? const Icon(
                    Icons.person_rounded,
                    color: AppColors.textMuted,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: context.textThemePrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'DNI ${p.dni}',
                  style: TextStyle(
                    color: context.textThemeMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
