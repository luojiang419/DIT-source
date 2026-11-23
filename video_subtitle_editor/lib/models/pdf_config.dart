class PDFConfig {
  final double thumbnailWidth;
  final double fontSize;
  final String? referenceImagePath;
  final double marginTop;
  final double marginBottom;
  final double marginLeft;
  final double marginRight;

  PDFConfig({
    this.thumbnailWidth = 200,
    this.fontSize = 10,
    this.referenceImagePath,
    this.marginTop = 30,
    this.marginBottom = 30,
    this.marginLeft = 30,
    this.marginRight = 30,
  });

  PDFConfig copyWith({
    double? thumbnailWidth,
    double? fontSize,
    String? referenceImagePath,
    double? marginTop,
    double? marginBottom,
    double? marginLeft,
    double? marginRight,
  }) {
    return PDFConfig(
      thumbnailWidth: thumbnailWidth ?? this.thumbnailWidth,
      fontSize: fontSize ?? this.fontSize,
      referenceImagePath: referenceImagePath ?? this.referenceImagePath,
      marginTop: marginTop ?? this.marginTop,
      marginBottom: marginBottom ?? this.marginBottom,
      marginLeft: marginLeft ?? this.marginLeft,
      marginRight: marginRight ?? this.marginRight,
    );
  }
}
