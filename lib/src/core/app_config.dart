class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://31.220.89.103:8099',
  );
  static const uploadBaseUrl = String.fromEnvironment(
    'UPLOAD_BASE_URL',
    defaultValue: apiBaseUrl,
  );
  static const legacyUploadBaseUrl = 'http://173.212.203.153:8090';
  static const versionUrl = String.fromEnvironment(
    'VERSION_URL',
    defaultValue: 'http://31.220.89.103/verzija.json',
  );

  static const inkasantiPath = '/api/Inkasantis/';
  static const stanjaBrojilaPath = '/api/stanjebrojilas';
  static const maxOcitavanjePath = '/api/Ocitavanja_glavna/MaxPlusDate';
  static const ocitavanjaPath = '/apiV/ocitavanjas';
  static const napomenaUploadPath = '/api/vobNapomena/upload2';
  static const diagnosticsBaseUrl = String.fromEnvironment(
    'DIAGNOSTICS_BASE_URL',
    defaultValue: apiBaseUrl,
  );
  static const diagnosticsKey = String.fromEnvironment(
    'DIAGNOSTICS_UPLOAD_KEY',
  );
  static const diagnosticsPath = '/api/app-errors/batch';
}
