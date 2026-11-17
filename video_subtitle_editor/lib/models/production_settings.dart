class ProductionSettings {
  final String? production;
  final String? cinematographer;
  final String? operator;
  final String? director;
  final String? location;
  final String? company;

  ProductionSettings({
    this.production,
    this.cinematographer,
    this.operator,
    this.director,
    this.location,
    this.company,
  });

  Map<String, dynamic> toMap() {
    return {
      'production': production,
      'cinematographer': cinematographer,
      'operator': operator,
      'director': director,
      'location': location,
      'company': company,
    };
  }

  factory ProductionSettings.fromMap(Map<String, dynamic> map) {
    return ProductionSettings(
      production: map['production'],
      cinematographer: map['cinematographer'],
      operator: map['operator'],
      director: map['director'],
      location: map['location'],
      company: map['company'],
    );
  }
}
