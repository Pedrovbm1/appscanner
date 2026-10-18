enum PdfDestination { share, save }

class PdfOptions {
  const PdfOptions({
    this.includeOcr = true,
    this.compress = true,
    this.watermark = '',
    this.protect = false,
    this.password = '',
    this.destination = PdfDestination.share,
  });

  final bool includeOcr;
  final bool compress;
  final String watermark;
  final bool protect;
  final String password;
  final PdfDestination destination;
}
