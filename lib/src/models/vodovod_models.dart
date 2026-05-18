class InkasantiModel {
  const InkasantiModel({
    required this.idink,
    required this.idZaOcitavanja,
    required this.ime,
    required this.username,
    required this.password,
    required this.vidljivoStanje,
    required this.opomenaStanje,
  });

  final int idink;
  final String idZaOcitavanja;
  final String ime;
  final String username;
  final String password;
  final int vidljivoStanje;
  final int opomenaStanje;

  factory InkasantiModel.fromJson(Map<String, dynamic> json) {
    return InkasantiModel(
      idink: _asInt(json['idink'] ?? json['id']),
      idZaOcitavanja: _asString(json['id_za_ocitavanja']),
      ime: _asString(json['ime']),
      username: _asString(json['username']),
      password: _asString(json['password']),
      vidljivoStanje: _asInt(json['vidljivo_stanje']),
      opomenaStanje: _asInt(json['opomena_stanje']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'idink': idink,
      'id_za_ocitavanja': idZaOcitavanja,
      'ime': ime,
      'username': username,
      'password': password,
      'vidljivo_stanje': vidljivoStanje,
      'opomena_stanje': opomenaStanje,
    };
  }
}

class ReonSummary {
  const ReonSummary({
    required this.id,
    required this.naziv,
    required this.ukupno,
    required this.ocitano,
  });

  final String id;
  final String naziv;
  final int ukupno;
  final int ocitano;
}

class RutaSummary {
  const RutaSummary({
    required this.id,
    required this.naziv,
    required this.reonId,
    required this.ukupno,
    required this.ocitano,
  });

  final String id;
  final String naziv;
  final String reonId;
  final int ukupno;
  final int ocitano;
}

class OcitavanjeModel {
  const OcitavanjeModel({
    required this.id,
    required this.rbr,
    required this.idpot,
    required this.potrosac,
    required this.vodomjer,
    required this.adr,
    required this.lokacija,
    required this.idreon,
    required this.nazivReona,
    required this.idrute,
    required this.nazivRute,
    required this.idink,
    required this.inkasant,
    required this.stanje,
    required this.novoStanje,
    required this.saldo,
    required this.ocitano,
    required this.latitude,
    required this.longitude,
    required this.idstanjebrojila,
    required this.ocitavanjeGlavnoId,
    required this.isSynced,
  });

  final int id;
  final int rbr;
  final String idpot;
  final String potrosac;
  final String vodomjer;
  final String adr;
  final String lokacija;
  final String idreon;
  final String nazivReona;
  final String idrute;
  final String nazivRute;
  final String idink;
  final String inkasant;
  final int stanje;
  final int novoStanje;
  final String saldo;
  final String ocitano;
  final String latitude;
  final String longitude;
  final int idstanjebrojila;
  final int ocitavanjeGlavnoId;
  final bool isSynced;

  bool get isOcitano => novoStanje > 0 || ocitano.toLowerCase() == 'da';

  factory OcitavanjeModel.fromJson(Map<String, dynamic> json) {
    return OcitavanjeModel(
      id: _asInt(json['id']),
      rbr: _asInt(json['rbr']),
      idpot: _asString(json['idpot']),
      potrosac: _asString(json['potrosac']),
      vodomjer: _asString(json['vodomjer']),
      adr: _asString(json['adr']),
      lokacija: _asString(json['lokacija']),
      idreon: _asString(json['idreon']),
      nazivReona: _asString(json['naziv_reona']),
      idrute: _asString(json['idrute']),
      nazivRute: _asString(json['naziv_rute']),
      idink: _asString(json['idink']),
      inkasant: _asString(json['inkasant']),
      stanje: _asInt(json['stanje']),
      novoStanje: _asInt(json['novo_stanje']),
      saldo: _asString(json['saldo']),
      ocitano: _asString(json['ocitano']),
      latitude: _asString(json['latitude']),
      longitude: _asString(json['longitude']),
      idstanjebrojila: _asInt(json['idstanjebrojila']),
      ocitavanjeGlavnoId: _asInt(json['ocitavanje_glavno_id']),
      isSynced: _asBool(json['isSynced'] ?? json['is_synced']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'rbr': rbr,
      'idpot': idpot,
      'potrosac': potrosac,
      'vodomjer': vodomjer,
      'adr': adr,
      'lokacija': lokacija,
      'idreon': idreon,
      'naziv_reona': nazivReona,
      'idrute': idrute,
      'naziv_rute': nazivRute,
      'idink': idink,
      'inkasant': inkasant,
      'stanje': stanje,
      'novo_stanje': novoStanje,
      'saldo': saldo,
      'ocitano': ocitano,
      'latitude': latitude,
      'longitude': longitude,
      'idstanjebrojila': idstanjebrojila,
      'ocitavanje_glavno_id': ocitavanjeGlavnoId,
      'isSynced': isSynced,
    };
  }

  OcitavanjeModel copyWith({
    int? novoStanje,
    bool? isSynced,
    String? ocitano,
    int? idstanjebrojila,
    String? latitude,
    String? longitude,
  }) {
    return OcitavanjeModel(
      id: id,
      rbr: rbr,
      idpot: idpot,
      potrosac: potrosac,
      vodomjer: vodomjer,
      adr: adr,
      lokacija: lokacija,
      idreon: idreon,
      nazivReona: nazivReona,
      idrute: idrute,
      nazivRute: nazivRute,
      idink: idink,
      inkasant: inkasant,
      stanje: stanje,
      novoStanje: novoStanje ?? this.novoStanje,
      saldo: saldo,
      ocitano: ocitano ?? this.ocitano,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      idstanjebrojila: idstanjebrojila ?? this.idstanjebrojila,
      ocitavanjeGlavnoId: ocitavanjeGlavnoId,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

class OcitavanjeGlavnoModel {
  const OcitavanjeGlavnoModel({
    required this.id,
    required this.dateShouldFinish,
  });

  final int id;
  final String dateShouldFinish;

  factory OcitavanjeGlavnoModel.fromJson(Map<String, dynamic> json) {
    return OcitavanjeGlavnoModel(
      id: _asInt(json['id']),
      dateShouldFinish: _asString(
        json['dateShouldFinish'] ?? json['date_should_finish'],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'date_should_finish': dateShouldFinish};
  }
}

class StanjeBrojilaModel {
  const StanjeBrojilaModel({
    required this.id,
    required this.opis,
    required this.oznaka,
  });

  final int id;
  final String opis;
  final String oznaka;

  String get label {
    final parts = [
      id.toString(),
      opis,
      oznaka,
    ].where((part) => part.trim().isNotEmpty).toList();
    return parts.join(' ');
  }

  String get shortLabel {
    if (oznaka.trim().isNotEmpty) return oznaka;
    if (opis.trim().isNotEmpty) return opis;
    return id.toString();
  }

  factory StanjeBrojilaModel.fromJson(Map<String, dynamic> json) {
    return StanjeBrojilaModel(
      id: _asInt(json['stanjebrojila_id']),
      opis: _asString(json['stanjebrojila_opis']),
      oznaka: _asString(json['stanjebrojila_oznaka']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stanjebrojila_id': id,
      'stanjebrojila_opis': opis,
      'stanjebrojila_oznaka': oznaka,
    };
  }
}

class BackendNapomenaModel {
  const BackendNapomenaModel({
    required this.id,
    required this.idpot,
    required this.vodomjer,
    required this.imepot,
    required this.napomena,
    required this.inkId,
    required this.isPrijava,
    required this.profil,
    required this.imageUrl,
    required this.datum,
    required this.zavrseno,
  });

  final int id;
  final String idpot;
  final String vodomjer;
  final String imepot;
  final String napomena;
  final String inkId;
  final bool isPrijava;
  final String profil;
  final String imageUrl;
  final DateTime? datum;
  final bool zavrseno;

  factory BackendNapomenaModel.fromJson(Map<String, dynamic> json) {
    return BackendNapomenaModel(
      id: _asInt(json['napomena_id'] ?? json['napomenaId'] ?? json['id']),
      idpot: _asString(json['idpot']),
      vodomjer: _asString(json['vodomjer']),
      imepot: _asString(json['imepot']),
      napomena: _asString(json['napomena']),
      inkId: _asString(json['ink_id'] ?? json['inkId']),
      isPrijava: _asBool(json['is_prijava'] ?? json['isPrijava']),
      profil: _asString(json['profil']),
      imageUrl: _asString(json['imageUrl'] ?? json['image_url']),
      datum: DateTime.tryParse(_asString(json['datum'])),
      zavrseno: _asBool(json['zavrseno']),
    );
  }
}

class NapomenaDraft {
  const NapomenaDraft({
    required this.localId,
    required this.vodomjer,
    required this.idpot,
    required this.imepot,
    required this.inkId,
    required this.napomena,
    required this.isPrijava,
    required this.profil,
    required this.slikaPath,
  });

  final int localId;
  final String vodomjer;
  final String idpot;
  final String imepot;
  final String inkId;
  final String napomena;
  final bool isPrijava;
  final String profil;
  final String slikaPath;

  factory NapomenaDraft.fromJson(Map<String, dynamic> json) {
    return NapomenaDraft(
      localId: _asInt(json['local_id']),
      vodomjer: _asString(json['vodomjer']),
      idpot: _asString(json['idpot']),
      imepot: _asString(json['imepot']),
      inkId: _asString(json['ink_id']),
      napomena: _asString(json['napomena']),
      isPrijava: _asBool(json['is_prijava']),
      profil: _asString(json['profil']),
      slikaPath: _asString(json['slika']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_id': localId,
      'vodomjer': vodomjer,
      'idpot': idpot,
      'imepot': imepot,
      'ink_id': inkId,
      'napomena': napomena,
      'is_prijava': isPrijava,
      'profil': profil,
      'slika': slikaPath,
    };
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _asString(Object? value) {
  return value?.toString() ?? '';
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  return text == 'true' || text == '1' || text == 'da';
}
