import 'package:flutter/material.dart';

/// Display metadata for the committed demo profiles. Unknown ids still render
/// via [PersonaMeta.forId]'s fallback, so this never gates the profile list.
class PersonaMeta {
  final IconData icon;
  final String name;
  final String sector;

  const PersonaMeta({
    required this.icon,
    required this.name,
    required this.sector,
  });

  static const _known = <String, PersonaMeta>{
    'lakshmi_vendor_001': PersonaMeta(
      icon: Icons.storefront_outlined,
      name: 'Lakshmi',
      sector: 'Street food vendor',
    ),
    'thin_file_002': PersonaMeta(
      icon: Icons.description_outlined,
      name: 'Thin File',
      sector: 'Under 6 months of history',
    ),
    'dormancy_gap_003': PersonaMeta(
      icon: Icons.store_mall_directory_outlined,
      name: 'Dormancy Gap',
      sector: 'Kirana store',
    ),
    'ramesh_carpentry_004': PersonaMeta(
      icon: Icons.handyman_outlined,
      name: 'Ramesh',
      sector: 'Carpentry / small trade',
    ),
    'meera_tailor_005': PersonaMeta(
      icon: Icons.content_cut_outlined,
      name: 'Meera',
      sector: 'Tailoring studio',
    ),
    'arjun_kirana_006': PersonaMeta(
      icon: Icons.shopping_basket_outlined,
      name: 'Arjun',
      sector: 'Kirana store',
    ),
    // NOT a borrower. This entry stands for a submitted statement that was
    // machine-generated, and the sector line says so outright: every other
    // card in the rail represents a real MSME, and this one must never be
    // mistaken for a seventh.
    'uniform_trail_007': PersonaMeta(
      icon: Icons.copy_all_outlined,
      name: 'Uniform Trail',
      sector: 'Fabricated — data-integrity demo',
    ),
  };

  static PersonaMeta forId(String id) {
    final known = _known[id];
    if (known != null) return known;

    final pretty = id
        .split(RegExp(r'[_\-]'))
        .where((part) => part.isNotEmpty && int.tryParse(part) == null)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');

    return PersonaMeta(
      icon: Icons.person_outline,
      name: pretty.isEmpty ? id : pretty,
      sector: id,
    );
  }
}
