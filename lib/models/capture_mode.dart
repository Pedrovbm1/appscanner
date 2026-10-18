enum CaptureMode { docs, id, card, slides }

extension CaptureModeInfo on CaptureMode {
  String get label => switch (this) {
        CaptureMode.docs => 'Docs',
        CaptureMode.id => 'ID',
        CaptureMode.card => 'Tarjeta',
        CaptureMode.slides => 'Diapositivas',
      };

  String get hint => switch (this) {
        CaptureMode.docs => 'Coloca el documento dentro del marco',
        CaptureMode.id => 'Alinea la identificación dentro del marco',
        CaptureMode.card => 'Alinea la tarjeta dentro del marco',
        CaptureMode.slides => 'Alinea la diapositiva dentro del marco',
      };

  double get frameRatio => switch (this) {
        CaptureMode.docs => 0.707,
        CaptureMode.id => 1.586,
        CaptureMode.card => 1.586,
        CaptureMode.slides => 16 / 9,
      };
}
