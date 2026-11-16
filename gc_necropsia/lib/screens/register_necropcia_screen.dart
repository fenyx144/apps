import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gc_necropcia/utils/constants.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/cenco.dart';
import '../models/galpon.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../utils/toast_helper.dart';
import '../utils/dialog_helper.dart';
import '../utils/necropsias_origen.dart';
import '../services/vosk_service.dart';
import '../widgets/app_bar.dart' show buildAppBar;
import '../widgets/app_drawer.dart';
import 'image_editor_screen.dart';

class RegisterNecropciaScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final bool isEditing;
  final VoidCallback? onSaveRequested;
  final ValueNotifier<VoidCallback?>? saveNotifier;

  const RegisterNecropciaScreen({
    super.key,
    this.initialData,
    this.isEditing = false,
    this.onSaveRequested,
    this.saveNotifier,
  });

  @override
  State<RegisterNecropciaScreen> createState() =>
      _RegisterNecropciaScreenState();
}

class _RegisterNecropciaScreenState extends State<RegisterNecropciaScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  int _observationFieldKeySeed =
      0; // fuerza rebuild de campos con initialValue (observaciones)
  final Map<String, TextEditingController> _observationControllers = {};
  final TextEditingController _fechaController = TextEditingController();
  final TextEditingController _campController = TextEditingController();
  final TextEditingController _edadController = TextEditingController();
  final TextEditingController _diagnosticoPresuntivoController =
      TextEditingController();
  final TextEditingController _codigoNecropsiaController =
      TextEditingController();

  // Dictado por voz (VOSK offline, modelo cargado desde Splash/Login vía VoskService)
  bool _speechListening = false;
  bool _micBlinkVisible = true;
  Timer? _micBlinkTimer;
  String _committedListeningText = '';
  TextEditingController? _currentListeningController;
  void Function(String)? _currentOnTextUpdated;
  StreamSubscription<String?>? _voskResultSub;
  StreamSubscription<String?>? _voskPartialSub;
  void _onVoskStateChanged() => setState(() {});

  // Tracking de hora de inicio y fin (solo para nuevos registros)
  DateTime? _horaInicioRegistro;

  // Método para registrar hora de inicio cuando se ingresa cualquier valor
  void _registerStartTimeIfNeeded() {
    if (!widget.isEditing && _horaInicioRegistro == null) {
      _horaInicioRegistro = DateTime.now();
      debugPrint(
        '🕐 Hora de inicio de registro registrada: $_horaInicioRegistro',
      );
    }
  }

  List<Cenco> _cencos = [];
  List<Galpon> _galpones = [];

  String? _selectedCenco;
  String? _selectedGalpon;
  String? _selectedPlanId;
  String _selectedPlanLabel = '';
  List<Map<String, dynamic>> _planSuggestions = [];
  bool _isLoadingPlanSuggestions = false;

  OrigenNecropsia _origen = OrigenNecropsia.grs;
  String? _griSeleccion;
  List<Map<String, dynamic>> _griOpciones = [];
  bool _cargandoGri = false;
  final TextEditingController _codigoOrigenExtController =
      TextEditingController();

  DateTime _selectedDate = DateTime.now();

  // TabController para las categorías
  late TabController _tabController;

  // Estados de expansión para subsecciones inmunológico (todos expandidos por defecto)
  Map<String, bool> _inmunologicoSubsectionsExpanded = {
    'INDICE BURSAL': true,
    'MUCOSA DE LA BURSA': true,
    'TIMOS': true,
  };

  // Estados de expansión para subsecciones digestivo
  Map<String, bool> _digestivoSubsectionsExpanded = {};

  // Estados de expansión para subsecciones respiratorio
  Map<String, bool> _respiratorioSubsectionsExpanded = {};

  // Estados de expansión para subsecciones física
  Map<String, bool> _fisicaSubsectionsExpanded = {};

  // Datos del sistema inmunológico - cada subnivel tiene 5 checkboxes
  Map<String, Map<String, List<bool>>> _inmunologicoData = {
    'INDICE BURSAL': {
      'Normal': [false, false, false, false, false],
      'Atrofia': [false, false, false, false, false],
      'Severa Atrofia': [false, false, false, false, false],
    },
    'MUCOSA DE LA BURSA': {
      'Normal': [false, false, false, false, false],
      'Petequias': [false, false, false, false, false],
      'Hemorragia': [false, false, false, false, false],
    },
    'TIMOS': {
      'Normal': [false, false, false, false, false],
      'Atrofiados': [false, false, false, false, false],
      'Aspecto Normal': [false, false, false, false, false],
      'Congestionado': [false, false, false, false, false],
    },
  };

  // Datos para otras secciones
  Map<String, Map<String, List<bool>>> _digestivoData = {};
  Map<String, Map<String, List<bool>>> _respiratorioData = {};
  Map<String, Map<String, List<bool>>> _fisicaData = {};

  Map<String, String> _inmunologicoObservaciones = {
    'INDICE BURSAL': '',
    'MUCOSA DE LA BURSA': '',
    'TIMOS': '',
  };

  Map<String, String> _digestivoObservaciones = {};
  Map<String, String> _respiratorioObservaciones = {};
  Map<String, String> _fisicaObservaciones = {};

  // Permitir hasta 3 imágenes por nivel
  Map<String, List<XFile?>> _inmunologicoImages = {
    'INDICE BURSAL': [null, null, null],
    'MUCOSA DE LA BURSA': [null, null, null],
    'TIMOS': [null, null, null],
  };

  Map<String, List<XFile?>> _digestivoImages = {};
  Map<String, List<XFile?>> _respiratorioImages = {};
  Map<String, List<XFile?>> _fisicaImages = {};

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 5, vsync: this);

    // Registrar hora de inicio solo para nuevos registros (no ediciones)
    if (!widget.isEditing) {
      _horaInicioRegistro = DateTime.now();
      debugPrint('🕐 Hora de inicio de registro: $_horaInicioRegistro');
    }

    _initializeDigestivoData();
    _initializeRespiratorioData();
    _initializeFisicaData();

    // Valor por defecto (en modo edición será sobreescrito por _loadInitialData()).
    _fechaController.text = _formatDateForDisplay(_selectedDate);

    // Cargar CENCOS y, si aplica, hidratar initialData.
    _loadCencosFromLocal();

    if (!widget.isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadCodigoNecropsiaPreview();
      });
    }

    // Configurar el callback de guardado si existe
    if (widget.saveNotifier != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Configurar el callback para que apunte a saveForm
        // Wrapper para convertir Future<void> a VoidCallback
        widget.saveNotifier!.value = () {
          saveForm(); // No esperamos el resultado, el flujo interno maneja todo
        };
      });
    }
    final vosk = VoskService.instance;
    vosk.addListener(_onVoskStateChanged);
    // Asegura que la carga esté en curso o ya lista (Splash la inicia; si no, la iniciamos aquí)
    vosk.init();
  }

  /// [onTextUpdated] se llama cuando el dictado añade texto (p. ej. para sincronizar mapas de observaciones).
  Future<void> _startListeningForController(
    TextEditingController controller, {
    void Function(String newText)? onTextUpdated,
  }) async {
    final vosk = VoskService.instance;
    if (!vosk.isReady || vosk.speechService == null) {
      if (vosk.isLoading) {
        showErrorToast(context, 'Cargando modelo de voz… Espera un momento.');
      } else if (vosk.error != null) {
        showErrorToast(context, vosk.error!);
      } else {
        showErrorToast(context, 'El dictado por voz no está disponible.');
      }
      return;
    }
    if (_speechListening) {
      await _stopListening();
      return;
    }
    _registerStartTimeIfNeeded();

    bool permissionOk = true;
    try {
      final status = await Permission.microphone.request();
      if (!mounted) return;
      if (status.isDenied) {
        showErrorToast(
          context,
          'Se necesita permiso de micrófono para dictar. Acepta cuando el sistema lo pida.',
        );
        return;
      }
      if (status.isPermanentlyDenied) {
        showErrorToast(
          context,
          'Permiso de micrófono denegado. Actívalo en Ajustes de la app.',
        );
        await openAppSettings();
        return;
      }
      if (status.isRestricted) {
        showErrorToast(context, 'El micrófono está restringido en este dispositivo.');
        return;
      }
    } on PlatformException catch (_) {
      permissionOk = false;
    } on Exception catch (_) {
      permissionOk = false;
    }

    if (!permissionOk && mounted) {
      showErrorToast(
        context,
        'No se pudo comprobar el permiso. Cierra la app y ábrela de nuevo, luego prueba el dictado.',
      );
      return;
    }

    _currentListeningController = controller;
    _currentOnTextUpdated = onTextUpdated;

    String extractTextFromJson(String? raw) {
      if (raw == null || raw.trim().isEmpty) return '';
      final s = raw.trim();
      try {
        final decoded = jsonDecode(s);
        if (decoded is Map) {
          final t = decoded['text'] ?? decoded['partial'];
          if (t != null) return t.toString().trim();
        }
      } catch (_) {}
      return s; // texto plano si no es JSON
    }

    _committedListeningText = controller.text;

    void onResult(String? result) {
      final c = _currentListeningController;
      final cb = _currentOnTextUpdated;
      final text = extractTextFromJson(result);
      if (c == null || text.isEmpty) return;
      c.text = _committedListeningText + (_committedListeningText.isNotEmpty ? ' ' : '') + text;
      _committedListeningText = c.text;
      cb?.call(c.text);
      if (mounted) setState(() {});
    }

    final speechService = vosk.speechService!;
    _voskResultSub = speechService.onResult().listen(onResult);
    _voskPartialSub = speechService.onPartial().listen((partialRaw) {
      final c = _currentListeningController;
      if (c == null || !mounted) return;
      final partial = extractTextFromJson(partialRaw);
      c.text = _committedListeningText + (_committedListeningText.isNotEmpty && partial.isNotEmpty ? ' ' : '') + partial;
      if (mounted) setState(() {});
    });

    await speechService.start();
    if (mounted) {
      setState(() => _speechListening = true);
      _micBlinkTimer?.cancel();
      _micBlinkTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        if (mounted) setState(() => _micBlinkVisible = !_micBlinkVisible);
      });
    }
  }

  /// Detiene el dictado por voz cuando el usuario lo desee.
  Future<void> _stopListening() async {
    _micBlinkTimer?.cancel();
    _micBlinkTimer = null;
    await _voskResultSub?.cancel();
    await _voskPartialSub?.cancel();
    _voskResultSub = null;
    _voskPartialSub = null;
    _currentListeningController = null;
    _currentOnTextUpdated = null;
    await VoskService.instance.speechService?.stop();
    if (mounted) setState(() {
      _speechListening = false;
      _committedListeningText = '';
    });
  }

  /// Icono de micrófono: parpadea, borde y rojo cuando está escuchando; al pulsar de nuevo se detiene.
  Widget _buildMicIcon({double size = 22}) {
    final icon = AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _speechListening ? (_micBlinkVisible ? 1 : 0.4) : 1,
      child: Icon(
        _speechListening ? Icons.mic : Icons.mic_none_outlined,
        color: _speechListening ? Colors.red : AppColors.textMuted,
        size: size,
      ),
    );
    if (!_speechListening) return icon;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.red.withOpacity(_micBlinkVisible ? 0.9 : 0.35),
          width: 2,
        ),
      ),
      child: icon,
    );
  }

  @override
  void dispose() {
    _micBlinkTimer?.cancel();
    VoskService.instance.removeListener(_onVoskStateChanged);
    _voskResultSub?.cancel();
    _voskPartialSub?.cancel();
    VoskService.instance.speechService?.stop();
    _tabController.dispose();
    _fechaController.dispose();
    _codigoNecropsiaController.dispose();
    _codigoOrigenExtController.dispose();
    _campController.dispose();
    _edadController.dispose();
    _diagnosticoPresuntivoController.dispose();
    for (final c in _observationControllers.values) {
      c.dispose();
    }
    _observationControllers.clear();
    super.dispose();
  }

  void _initializeDigestivoData() {
    _digestivoSubsectionsExpanded = {
      'Hígados': true,
      'Vesícula biliar': true,
      'Erosión de molleja': true,
      'Retracción del páncreas': true,
      'Absorción del saco vitelino': true,
      'Enteritis': true,
      'Contenido cecal': true,
      'Alimento sin digerir': true,
      'Heces anaranjadas': true,
      'Lesión oral': true,
      'Tonicidad Intestinal': true,
    };
    _digestivoData = {
      'Hígados': {
        'Normal': [false, false, false, false, false],
        'Esteatósico': [false, false, false, false, false],
        'Tmño Normal': [false, false, false, false, false],
        'Hipertrofiado': [false, false, false, false, false],
      },
      'Vesícula biliar': {
        'Color Normal': [false, false, false, false, false],
        'Color Claro': [false, false, false, false, false],
        'Tmño Normal': [false, false, false, false, false],
        'Atrofiado': [false, false, false, false, false],
        'Hipertrofiado': [false, false, false, false, false],
      },
      'Erosión de molleja': {
        'Normal': [false, false, false, false, false],
        'Grado 1': [false, false, false, false, false],
        'Grado 2': [false, false, false, false, false],
        'Grado 3': [false, false, false, false, false],
        'Grado 4': [false, false, false, false, false],
      },
      'Retracción del páncreas': {
        'Normal': [false, false, false, false, false],
        'Retraído': [false, false, false, false, false],
      },
      'Absorción del saco vitelino': {
        'Si': [false, false, false, false, false],
        'No': [false, false, false, false, false],
      },
      'Enteritis': {
        'Normal': [false, false, false, false, false],
        'Leve': [false, false, false, false, false],
        'Moderado': [false, false, false, false, false],
        'Severo': [false, false, false, false, false],
      },
      'Contenido cecal': {
        'Normal': [false, false, false, false, false],
        'Gas': [false, false, false, false, false],
        'Espuma': [false, false, false, false, false],
      },
      'Alimento sin digerir': {
        'Si': [false, false, false, false, false],
        'No': [false, false, false, false, false],
      },
      'Heces anaranjadas': {
        'Si': [false, false, false, false, false],
        'No': [false, false, false, false, false],
      },
      'Lesión oral': {
        'Si': [false, false, false, false, false],
        'No': [false, false, false, false, false],
      },
      'Tonicidad Intestinal': {
        'Buena': [false, false, false, false, false],
        'Regular': [false, false, false, false, false],
        'Mala': [false, false, false, false, false],
      },
    };
    // Inicializar observaciones por nivel
    _digestivoObservaciones = {
      'Hígados': '',
      'Vesícula biliar': '',
      'Erosión de molleja': '',
      'Retracción del páncreas': '',
      'Absorción del saco vitelino': '',
      'Enteritis': '',
      'Contenido cecal': '',
      'Alimento sin digerir': '',
      'Heces anaranjadas': '',
      'Lesión oral': '',
      'Tonicidad Intestinal': '',
    };
    // Inicializar imágenes por nivel
    _digestivoImages = {
      'Hígados': [null, null, null],
      'Vesícula biliar': [null, null, null],
      'Erosión de molleja': [null, null, null],
      'Retracción del páncreas': [null, null, null],
      'Absorción del saco vitelino': [null, null, null],
      'Enteritis': [null, null, null],
      'Contenido cecal': [null, null, null],
      'Alimento sin digerir': [null, null, null],
      'Heces anaranjadas': [null, null, null],
      'Lesión oral': [null, null, null],
      'Tonicidad Intestinal': [null, null, null],
    };
  }

  void _initializeRespiratorioData() {
    _respiratorioSubsectionsExpanded = {
      'Tráquea': true,
      'Pulmón': true,
      'Sacos aéreos': true,
    };
    _respiratorioData = {
      'Tráquea': {
        'Normal': [false, false, false, false, false],
        'Leve': [false, false, false, false, false],
        'Moderada': [false, false, false, false, false],
        'Severa': [false, false, false, false, false],
      },
      'Pulmón': {
        'Normal': [false, false, false, false, false],
        'Neumónico': [false, false, false, false, false],
      },
      'Sacos aéreos': {
        'Normal': [false, false, false, false, false],
        'Turbio': [false, false, false, false, false],
        'Material Caseoso': [false, false, false, false, false],
      },
    };
    // Inicializar observaciones por nivel
    _respiratorioObservaciones = {
      'Tráquea': '',
      'Pulmón': '',
      'Sacos aéreos': '',
    };
    // Inicializar imágenes por nivel
    _respiratorioImages = {
      'Tráquea': [null, null, null],
      'Pulmón': [null, null, null],
      'Sacos aéreos': [null, null, null],
    };
  }

  void _initializeFisicaData() {
    _fisicaSubsectionsExpanded = {
      'Pododermatitis': true,
      'Color de tarsos': true,
    };
    _fisicaData = {
      'Pododermatitis': {
        'Grado 0': [false, false, false, false, false],
        'Grado 1': [false, false, false, false, false],
        'Grado 2': [false, false, false, false, false],
        'Grado 3': [false, false, false, false, false],
        'Grado 4': [false, false, false, false, false],
      },
      'Color de tarsos': {
        '3.5': [false, false, false, false, false],
        '4.0': [false, false, false, false, false],
        '4.5': [false, false, false, false, false],
        '5.0': [false, false, false, false, false],
        '5.5': [false, false, false, false, false],
        '6.0': [false, false, false, false, false],
      },
    };
    // Inicializar observaciones por nivel
    _fisicaObservaciones = {'Pododermatitis': '', 'Color de tarsos': ''};
    // Inicializar imágenes por nivel
    _fisicaImages = {
      'Pododermatitis': [null, null, null],
      'Color de tarsos': [null, null, null],
    };
  }

  /// Carga CENCOS desde el storage local
  Future<void> _loadCencosFromLocal() async {
    final storage = context.read<StorageService>();

    // Cargar siempre desde storage local
    final cencosData = storage.getCencosLocal();

    if (cencosData.isNotEmpty) {
      // Convertir a objetos Cenco
      final cencos = cencosData
          .map(
            (e) => Cenco(
              codigo: e['codigo']?.toString() ?? '',
              nombre: e['nombre']?.toString() ?? '',
              edad: e['edad']?.toString() ?? '',
              fecIngMin: e['fec_ing_min']?.toString(),
            ),
          )
          .toList();

      setState(() {
        _cencos = cencos;
      });

      debugPrint('✅ CENCOS cargados desde storage local: ${cencos.length}');

      // Si estamos editando, cargar los datos iniciales después de cargar los cencos
      if (widget.isEditing && widget.initialData != null) {
        _loadInitialData();
      } else {
        _loadCodigoNecropsiaPreview();
      }
    } else {
      // Si no hay datos locales, mostrar mensaje pero no cargar desde API
      debugPrint(
        '⚠️ No hay información en storage local. Por favor, descargue los CENCOS desde el menú.',
      );
      setState(() {
        _cencos = [];
      });

      // Si estamos editando, cargar los datos iniciales de todas formas
      if (widget.isEditing && widget.initialData != null) {
        _loadInitialData();
      } else {
        _loadCodigoNecropsiaPreview();
      }
    }
  }

  Future<void> _loadCodigoNecropsiaPreview() async {
    if (widget.isEditing) return;
    if (!_esOrigenExtTp) {
      if (mounted) {
        setState(() => _codigoNecropsiaController.text = '');
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _codigoNecropsiaController.text = 'Cargando...';
    });
    try {
      final res = await ApiService().fetchCodigoNecropsia();
      if (!mounted) return;
      if (res['success'] == true) {
        final codigo = res['codigoNecropsia']?.toString().trim() ?? '';
        setState(() {
          _codigoNecropsiaController.text = codigo;
        });
      } else {
        final msg = res['message']?.toString() ?? 'No disponible';
        debugPrint('Preview código necropsia: $msg');
        setState(() {
          _codigoNecropsiaController.text = '';
        });
      }
    } catch (e) {
      debugPrint('No se pudo cargar preview código necropsia: $e');
      if (!mounted) return;
      setState(() {
        _codigoNecropsiaController.text = '';
      });
    }
  }

  Widget _buildCodigoNecropsiaField() {
    return TextFormField(
      controller: _codigoNecropsiaController,
      readOnly: true,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: 'Código necropsia',
        floatingLabelBehavior: FloatingLabelBehavior.always,
        hintText: _codigoNecropsiaController.text.isEmpty
            ? 'Requiere conexión al servidor'
            : null,
        labelStyle: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: AppColors.cardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 16,
        ),
      ),
    );
  }

  bool get _esOrigenExtTp =>
      _origen == OrigenNecropsia.externo || _origen == OrigenNecropsia.traspatio;

  bool get _esGrs => _origen == OrigenNecropsia.grs;

  void _onOrigenChanged(OrigenNecropsia? nuevo) {
    if (nuevo == null) return;
    setState(() {
      _origen = nuevo;
      _griSeleccion = null;
      _griOpciones = [];
      _selectedPlanId = null;
      _selectedPlanLabel = '';
      _planSuggestions = [];
      if (_esOrigenExtTp) {
        _selectedCenco = null;
        _selectedGalpon = null;
        _galpones = [];
        _campController.clear();
        _edadController.clear();
      } else {
        _codigoOrigenExtController.clear();
        _codigoNecropsiaController.clear();
      }
    });
    if (_esOrigenExtTp) {
      _loadCodigoNecropsiaPreview();
    }
  }

  Future<void> _cargarGriOpciones() async {
    if (!_esGrs ||
        _selectedCenco == null ||
        _selectedGalpon == null ||
        _campController.text.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _griOpciones = [];
          if (_griSeleccion != null && _griSeleccion!.isNotEmpty) {
            // conservar selección en edición
          } else {
            _griSeleccion = null;
          }
        });
      }
      return;
    }
    final granja = _selectedCenco!.length >= 3
        ? _selectedCenco!.substring(0, 3)
        : _selectedCenco!;
    setState(() => _cargandoGri = true);
    final campania = _campController.text.trim();
    debugPrint(
      '🔎 GRI: granja=$granja campania=$campania galpon=$_selectedGalpon',
    );
    final res = await ApiService().buscarGriDisponibles(
      granja: granja,
      campania: campania,
      galpon: _selectedGalpon!,
      modulo: 'NECROPSIA',
    );
    if (!mounted) return;
    final items = (res['items'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        <Map<String, dynamic>>[];
    setState(() {
      _cargandoGri = false;
      if (res['success'] == true) {
        _griOpciones = items;
      } else {
        _griOpciones = [];
      }
    });
    if (res['success'] != true) {
      final msg = res['message']?.toString() ??
          'No se pudieron cargar las GRI disponibles';
      debugPrint('❌ GRI: $msg');
      if (mounted) showErrorToast(context, msg);
    } else if (items.isEmpty && mounted) {
      showErrorToast(
        context,
        'No hay GRI disponibles para granja $granja, campaña $campania y galpón $_selectedGalpon',
      );
    }
  }

  String _griOptionLabel(Map<String, dynamic> item) {
    final label = item['label']?.toString();
    if (label != null && label.isNotEmpty) return label;
    final cod = item['codigoGri']?.toString() ??
        '${item['tserie'] ?? ''}-${item['tnumfac'] ?? ''}';
    var fec = item['tfectra']?.toString() ?? '';
    if (fec.contains('-') && fec.length >= 10) {
      final p = fec.split('-');
      if (p.length >= 3) fec = '${p[2]}/${p[1]}/${p[0]}';
    }
    final parts = <String>[];
    final m = (item['tcantidM'] as num?)?.toDouble() ?? 0;
    final h = (item['tcantidH'] as num?)?.toDouble() ?? 0;
    if (m > 0) parts.add('M: ${m == m.roundToDouble() ? m.toInt() : m}');
    if (h > 0) parts.add('H: ${h == h.roundToDouble() ? h.toInt() : h}');
    final cantStr = parts.join(', ');
    return cantStr.isNotEmpty ? '$cod | $fec | $cantStr' : '$cod | $fec';
  }

  String _griOptionValue(Map<String, dynamic> item) =>
      '${item['tdoc'] ?? ''}|${item['tserie'] ?? ''}|${item['tnumfac'] ?? ''}';

  InputDecoration _cabeceraInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Future<void> _pickFechaNecropsia() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(primary: AppColors.primary),
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (pickedDate != null) {
      setState(() {
        _selectedDate = pickedDate;
        _fechaController.text = _formatDateForDisplay(pickedDate);
        _registerStartTimeIfNeeded();
        _recalculateAgeAndCampania();
      });
    }
  }

  Widget _buildFechaField() {
    return TextFormField(
      controller: _fechaController,
      readOnly: true,
      decoration: _cabeceraInputDecoration('Fecha *').copyWith(
        suffixIcon: IconButton(
          icon: Icon(Icons.calendar_today, size: 20, color: AppColors.iconAccent),
          onPressed: _pickFechaNecropsia,
        ),
      ),
      onTap: _pickFechaNecropsia,
    );
  }

  /// Cabecera con scroll: evita que Origen/GRI queden fuera de pantalla en móviles.
  Widget _buildCabeceraScrollable(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.48;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: _buildCabeceraNecropsia(),
      ),
    );
  }

  Widget _buildOrigenProcesoRow() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<OrigenNecropsia>(
            isExpanded: true,
            value: _origen,
            decoration: _cabeceraInputDecoration('Origen *'),
            items: OrigenNecropsia.values
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(NecropsiasOrigen.origenLabel(o)),
                  ),
                )
                .toList(),
            onChanged: _onOrigenChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            readOnly: true,
            initialValue: 'Necropsias',
            decoration: _cabeceraInputDecoration('Proceso'),
          ),
        ),
      ],
    );
  }

  Widget _buildGrsGranjaCampRow() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: InkWell(
            onTap: () => _showSearchableDropdown<Cenco>(
              title: 'Seleccionar Granja',
              items: _cencos,
              getLabel: (cenco) => cenco.displayLabel,
              getValue: (cenco) => cenco.codigo,
              selectedValue: _selectedCenco,
              onSelected: (value) {
                setState(() {
                  _selectedCenco = value;
                  _selectedGalpon = null;
                  _griSeleccion = null;
                  _griOpciones = [];
                  _edadController.text = '';
                  _registerStartTimeIfNeeded();
                  if (value != null) {
                    _loadGalpones(value);
                    _recalculateAgeAndCampania();
                  } else {
                    _campController.text = '';
                    _edadController.text = '';
                  }
                });
              },
            ),
            child: InputDecorator(
              decoration: _cabeceraInputDecoration('Granja *').copyWith(
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                _selectedCenco != null && _cencos.isNotEmpty
                    ? _cencos
                        .firstWhere(
                          (c) => c.codigo == _selectedCenco,
                          orElse: () => _cencos.first,
                        )
                        .displayLabel
                    : 'Seleccione',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: TextFormField(
            controller: _campController,
            readOnly: true,
            decoration: _cabeceraInputDecoration('CAMP'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildGrsGalponEdadRow() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: InkWell(
            onTap: () {
              if (_selectedCenco == null || _selectedCenco!.isEmpty) {
                showErrorToast(context, 'Por favor, primero seleccione una granja');
                return;
              }
              _showSearchableDropdown<Galpon>(
                title: 'Seleccionar Galpón',
                items: _galpones,
                getLabel: (galpon) => galpon.tcodint,
                getValue: (galpon) => galpon.tcodint,
                selectedValue: _selectedGalpon,
                onSelected: (value) {
                  _registerStartTimeIfNeeded();
                  setState(() {
                    _selectedGalpon = value;
                    _griSeleccion = null;
                    _recalculateAgeAndCampania();
                  });
                },
              );
            },
            child: InputDecorator(
              decoration: _cabeceraInputDecoration('Galpón *').copyWith(
                suffixIcon: const Icon(Icons.arrow_drop_down),
              ),
              child: Text(
                _selectedGalpon ?? 'Seleccione',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: TextFormField(
            controller: _edadController,
            readOnly: true,
            decoration: _cabeceraInputDecoration('Edad'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildGriField() {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: (_griSeleccion != null && _griSeleccion!.isNotEmpty)
          ? _griSeleccion
          : null,
      decoration: _cabeceraInputDecoration('GRI *').copyWith(
        suffixIcon: _cargandoGri
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : null,
      ),
      hint: Text(
        _griOpciones.isEmpty
            ? 'Complete granja, campaña y galpón'
            : 'Seleccione GRI',
      ),
      items: _griOpciones
          .map(
            (item) => DropdownMenuItem<String>(
              value: _griOptionValue(item),
              child: Text(
                _griOptionLabel(item),
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _griOpciones.isEmpty
          ? null
          : (v) => setState(() => _griSeleccion = v),
    );
  }

  Widget _buildCabeceraExtTp() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFechaField(),
        const SizedBox(height: 12),
        TextFormField(
          controller: _codigoOrigenExtController,
          decoration: _cabeceraInputDecoration('Código origen *'),
          onChanged: (_) => _registerStartTimeIfNeeded(),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _edadController,
          keyboardType: TextInputType.number,
          decoration: _cabeceraInputDecoration('Edad (días, opcional)'),
          onChanged: (_) => _registerStartTimeIfNeeded(),
        ),
      ],
    );
  }

  Widget _buildCabeceraNecropsia() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Datos generales',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        _buildOrigenProcesoRow(),
        const SizedBox(height: 12),
        if (_esGrs) ...[
          _buildFechaField(),
          const SizedBox(height: 12),
          _buildGrsGranjaCampRow(),
          const SizedBox(height: 12),
          _buildGrsGalponEdadRow(),
        ] else
          _buildCabeceraExtTp(),
        const SizedBox(height: 12),
        if (_esGrs) _buildGriField() else _buildCodigoNecropsiaField(),
        if (_esGrs) ...[
          const SizedBox(height: 12),
          _buildPlanificacionField(),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  void _loadInitialData() {
    if (widget.initialData == null) return;

    final data = widget.initialData!;

    setState(() {
      final codigo =
          data['codigoNecropsia']?.toString().trim() ?? '';
      _codigoNecropsiaController.text =
          codigo.isNotEmpty ? codigo : '—';

      // Cargar fecha primero
      if (data['fectra'] != null) {
        try {
          _selectedDate = DateTime.parse(data['fectra'].toString());
          _fechaController.text = _formatDateForDisplay(_selectedDate);
        } catch (e) {
          // Si falla, usar fecha actual
        }
      }

      // Cargar cabecera
      _selectedCenco = data['granja']?.toString();
      _selectedGalpon = data['galpon']?.toString();
      _campController.text = data['campania']?.toString() ?? '';
      _edadController.text = data['edad']?.toString() ?? '';
      _diagnosticoPresuntivoController.text =
          data['diagnostico_presuntivo']?.toString() ?? '';
      _selectedPlanId = data['planId']?.toString();
      _selectedPlanLabel = data['planLabel']?.toString() ?? '';
      if ((_selectedPlanLabel.isEmpty) && _selectedPlanId != null && _selectedPlanId!.isNotEmpty) {
        _selectedPlanLabel = 'Plan seleccionado: $_selectedPlanId';
      }

      final origenStr = data['origen']?.toString() ?? '';
      if (origenStr.isNotEmpty) {
        _origen = NecropsiasOrigen.despliegueToOrigen(origenStr);
      } else if (_selectedCenco != null) {
        _origen = NecropsiasOrigen.inferirDesdeGranja(_selectedCenco!);
      }
      if (_esOrigenExtTp) {
        _codigoOrigenExtController.text = data['granja']?.toString() ?? '';
      }
      final griSel = data['gri_seleccion']?.toString() ?? '';
      if (griSel.isNotEmpty) {
        _griSeleccion = griSel;
      }

      // Cargar galpones si hay cenco seleccionado
      if (_selectedCenco != null) {
        _loadGalpones(_selectedCenco!, preserveSelected: true);
        // Recalcular edad y campaña después de cargar CENCOS (usar WidgetsBinding para asegurar que los cencos estén cargados)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _recalculateAgeAndCampania();
            _refreshPlanSuggestions();
            if (_esGrs) _cargarGriOpciones();
          }
        });
      }

      // Cargar registros
      final registros = data['registros'] as List<dynamic>? ?? [];

      // Agrupar registros por sistema
      final Map<String, Map<String, Map<String, List<bool>>>>
      registrosPorSistema = {};

      for (var registro in registros) {
        final sistema = registro['tsistema']?.toString() ?? '';
        final nivel = registro['tnivel']?.toString() ?? '';
        final parametro = registro['tparametro']?.toString() ?? '';
        final porcentaje1 = (registro['tporcentaje1'] as num?)?.toInt() ?? 0;
        final porcentaje2 = (registro['tporcentaje2'] as num?)?.toInt() ?? 0;
        final porcentaje3 = (registro['tporcentaje3'] as num?)?.toInt() ?? 0;
        final porcentaje4 = (registro['tporcentaje4'] as num?)?.toInt() ?? 0;
        final porcentaje5 = (registro['tporcentaje5'] as num?)?.toInt() ?? 0;
        final observacion = registro['tobservacion']?.toString() ?? '';

        // Convertir porcentajes a checkboxes (cada 20% = 1 checkbox)
        final checkboxes = [
          porcentaje1 >= 20,
          porcentaje2 >= 20,
          porcentaje3 >= 20,
          porcentaje4 >= 20,
          porcentaje5 >= 20,
        ];

        if (sistema.isNotEmpty && nivel.isNotEmpty && parametro.isNotEmpty) {
          registrosPorSistema.putIfAbsent(sistema, () => {});
          registrosPorSistema[sistema]!.putIfAbsent(nivel, () => {});
          registrosPorSistema[sistema]![nivel]![parametro] = checkboxes;

          // Cargar observación
          if (observacion.isNotEmpty) {
            if (sistema.contains('INMUNOLOGICO')) {
              _inmunologicoObservaciones[nivel] = observacion;
              _setObservationControllerTextIfExists(nivel, observacion);
            } else if (sistema.contains('DIGESTIVO')) {
              _digestivoObservaciones[nivel] = observacion;
              _setObservationControllerTextIfExists(nivel, observacion);
            } else if (sistema.contains('RESPIRATORIO')) {
              _respiratorioObservaciones[nivel] = observacion;
              _setObservationControllerTextIfExists(nivel, observacion);
            } else if (sistema.contains('FISICA')) {
              _fisicaObservaciones[nivel] = observacion;
              _setObservationControllerTextIfExists(nivel, observacion);
            }
          }
        }
      }

      // Actualizar datos de cada sistema
      for (var sistemaEntry in registrosPorSistema.entries) {
        final sistema = sistemaEntry.key;
        final niveles = sistemaEntry.value;

        if (sistema.contains('INMUNOLOGICO')) {
          for (var nivelEntry in niveles.entries) {
            final nivel = nivelEntry.key;
            if (_inmunologicoData.containsKey(nivel)) {
              _inmunologicoData[nivel]!.addAll(nivelEntry.value);
            }
          }
        } else if (sistema.contains('DIGESTIVO')) {
          for (var nivelEntry in niveles.entries) {
            final nivel = nivelEntry.key;
            if (_digestivoData.containsKey(nivel)) {
              _digestivoData[nivel]!.addAll(nivelEntry.value);
            }
          }
        } else if (sistema.contains('RESPIRATORIO')) {
          for (var nivelEntry in niveles.entries) {
            final nivel = nivelEntry.key;
            if (_respiratorioData.containsKey(nivel)) {
              _respiratorioData[nivel]!.addAll(nivelEntry.value);
            }
          }
        } else if (sistema.contains('FISICA')) {
          for (var nivelEntry in niveles.entries) {
            final nivel = nivelEntry.key;
            if (_fisicaData.containsKey(nivel)) {
              _fisicaData[nivel]!.addAll(nivelEntry.value);
            }
          }
        }
      }

      // Cargar imágenes
      final evidenciasCompletas =
          data['evidencias_completas'] as Map<String, dynamic>? ?? {};

      debugPrint(
        '📸 _loadInitialData - Cargando evidencias: ${evidenciasCompletas.length} niveles',
      );

      for (var evidenciaEntry in evidenciasCompletas.entries) {
        final nivelKey =
            evidenciaEntry.key; // Formato: "INMUNOLOGICO_INDICE BURSAL"
        final imagenes = evidenciaEntry.value as List<dynamic>? ?? [];

        debugPrint(
          '   📸 Procesando nivel: $nivelKey con ${imagenes.length} imágenes',
        );

        // Extraer sistema y nivel de la clave
        final parts = nivelKey.split('_');
        if (parts.length >= 2) {
          final sistemaKey = parts[0];
          final nivel = parts.sublist(1).join('_');

          // Convertir imágenes a XFile
          final imageFiles = <XFile?>[];
          for (var imagenData in imagenes) {
            if (imagenData is Map<String, dynamic>) {
              final imagePath = imagenData['path']?.toString() ?? '';
              if (imagePath.isNotEmpty) {
                final file = File(imagePath);
                if (file.existsSync()) {
                  imageFiles.add(XFile(imagePath));
                  debugPrint('     ✓ Imagen cargada: $imagePath');
                } else {
                  imageFiles.add(null);
                }
              } else {
                imageFiles.add(null);
              }
            } else if (imagenData is String) {
              // Si es una ruta directa (string)
              final file = File(imagenData);
              if (file.existsSync()) {
                imageFiles.add(XFile(imagenData));
              } else {
                imageFiles.add(null);
              }
            } else {
              imageFiles.add(null);
            }
          }

          // Asegurar que siempre haya 3 elementos
          while (imageFiles.length < 3) {
            imageFiles.add(null);
          }

          // Asignar a la estructura correspondiente
          if (sistemaKey == 'INMUNOLOGICO' &&
              _inmunologicoImages.containsKey(nivel)) {
            _inmunologicoImages[nivel] = imageFiles;
            debugPrint('     ✓ Imágenes asignadas a INMUNOLOGICO/$nivel');
          } else if (sistemaKey == 'DIGESTIVO' &&
              _digestivoImages.containsKey(nivel)) {
            _digestivoImages[nivel] = imageFiles;
            debugPrint('     ✓ Imágenes asignadas a DIGESTIVO/$nivel');
          } else if (sistemaKey == 'RESPIRATORIO' &&
              _respiratorioImages.containsKey(nivel)) {
            _respiratorioImages[nivel] = imageFiles;
            debugPrint('     ✓ Imágenes asignadas a RESPIRATORIO/$nivel');
          } else if (sistemaKey == 'FISICA' &&
              _fisicaImages.containsKey(nivel)) {
            _fisicaImages[nivel] = imageFiles;
            debugPrint('     ✓ Imágenes asignadas a FISICA/$nivel');
          } else {
            debugPrint(
              '     ⚠ Nivel no encontrado en estructuras: $sistemaKey/$nivel',
            );
          }
        }
      }
    });
  }

  /// Calcula la edad usando DATEDIFF(fecha_seleccionada, fec_ing_min) + 1
  /// También recalcula la campaña (últimos 3 dígitos del código CENCOS)
  void _recalculateAgeAndCampania() {
    if (_selectedCenco == null || _cencos.isEmpty) {
      return;
    }

    final selectedCenco = _cencos.firstWhere(
      (c) => c.codigo == _selectedCenco,
      orElse: () => _cencos.first,
    );

    // Recalcular campaña (últimos 3 dígitos del código CENCOS)
    if (_selectedCenco!.length >= 3) {
      _campController.text = _selectedCenco!.substring(
        _selectedCenco!.length - 3,
      );
    } else {
      _campController.text = '';
    }

    // La edad debe recalcularse/desplegarse recién cuando hay galpón seleccionado (tcodint).
    // Si no hay galpón, dejamos la edad en blanco para evitar mostrar un cálculo "prematuro".
    if (_selectedGalpon == null || _selectedGalpon!.isEmpty) {
      _edadController.text = '';
      _refreshPlanSuggestions();
      if (_esGrs) _cargarGriOpciones();
      return;
    }

    // Calcular edad usando fec_ing_min del galpón (tcodint). Fallback: fec_ing_min del CENCO.
    final selectedGalponObj =
        _galpones.where((g) => g.tcodint == _selectedGalpon).isNotEmpty
        ? _galpones.firstWhere((g) => g.tcodint == _selectedGalpon)
        : null;
    final String? fecIngMinToUse =
        (selectedGalponObj?.fecIngMin != null &&
            selectedGalponObj!.fecIngMin!.isNotEmpty)
        ? selectedGalponObj.fecIngMin
        : selectedCenco.fecIngMin;

    if (fecIngMinToUse != null && fecIngMinToUse.isNotEmpty) {
      try {
        // Parsear fec_ing_min (formato YYYY-MM-DD) sin zona horaria para evitar problemas
        final fecIngMinParts = fecIngMinToUse.split('-');
        if (fecIngMinParts.length != 3) {
          throw FormatException('Formato de fecha inválido: $fecIngMinToUse');
        }
        final fecIngMin = DateTime(
          int.parse(fecIngMinParts[0]), // año
          int.parse(fecIngMinParts[1]), // mes
          int.parse(fecIngMinParts[2]), // día
        );

        // Normalizar fecha seleccionada a solo fecha (sin hora) para comparación correcta
        final fechaSeleccionada = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
        );

        // Calcular diferencia en días (equivalente a DATEDIFF en MySQL)
        final diferencia = fechaSeleccionada.difference(fecIngMin).inDays;
        final edad = diferencia + 1;

        debugPrint('🔢 Cálculo de edad:');
        debugPrint('   - tcodint (galpón): $_selectedGalpon');
        debugPrint('   - fec_ing_min usada: $fecIngMinToUse');
        debugPrint(
          '   - fecha_seleccionada: ${fechaSeleccionada.toString().split(' ')[0]}',
        );
        debugPrint('   - diferencia (días): $diferencia');
        debugPrint('   - edad calculada: $edad');

        if (edad <= 0) {
          showErrorToast(
            context,
            'La fecha seleccionada es anterior a la fecha de ingreso. Por favor, seleccione otra fecha.',
          );
          // Limpiar fecha y edad cuando la fecha es inválida
          _fechaController.text = '';
          _edadController.text = '';
          return;
        }

        _edadController.text = edad.toString();
        _refreshPlanSuggestions();
      } catch (e) {
        debugPrint('❌ Error calculando edad: $e');
        debugPrint('   - fec_ing_min recibido: $fecIngMinToUse');
        // Limpiar fecha y edad si hay error al calcular
        _fechaController.text = '';
        _edadController.text = '';
        _refreshPlanSuggestions();
      }
    } else {
      // Si no hay fec_ing_min, usar la edad del CENCO (fallback)
      debugPrint(
        '⚠️ No hay fec_ing_min para galpón $_selectedGalpon (CENCO ${selectedCenco.codigo}). Fallback edad CENCO: ${selectedCenco.edad}',
      );
      _edadController.text = selectedCenco.edad;
      _refreshPlanSuggestions();
    }
    if (_esGrs) _cargarGriOpciones();
  }

  Future<bool> _checkInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  Future<void> _refreshPlanSuggestions() async {
    if (!mounted) return;
    if (_selectedCenco == null ||
        _selectedCenco!.isEmpty ||
        _selectedGalpon == null ||
        _selectedGalpon!.isEmpty ||
        _campController.text.trim().isEmpty ||
        _edadController.text.trim().isEmpty) {
      setState(() {
        _planSuggestions = [];
        _selectedPlanId = null;
        _selectedPlanLabel = '';
      });
      return;
    }

    final storage = context.read<StorageService>();
    final withinRange = storage.isDateWithinPlanMatchRange(_selectedDate);
    if (!withinRange) {
      final hasInternet = await _checkInternetConnection();
      if (hasInternet) {
        final desde = _selectedDate.subtract(const Duration(days: 30));
        final hasta = _selectedDate.add(const Duration(days: 30));
        final api = ApiService();
        final dl = await api.downloadPlanMatchCandidates(
          desde: desde,
          hasta: hasta,
        );
        if (dl['success'] == true) {
          final candidatos = (dl['candidatos'] as List<dynamic>)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          await storage.savePlanMatchCandidates(
            candidates: candidatos,
            desde: desde,
            hasta: hasta,
          );
        } else {
          if (mounted) {
            showInfoToast(
              context,
              'No se pudo actualizar candidatos de planificación: ${dl['message'] ?? ''}',
            );
          }
        }
      } else {
        if (mounted) {
          showInfoToast(
            context,
            'Sin internet y fuera de rango cacheado. Descargue en la nube para actualizar candidatos.',
          );
        }
      }
    }

    final granja = _selectedCenco!.length >= 3
        ? _selectedCenco!.substring(0, 3)
        : _selectedCenco!;
    final camp = _campController.text.trim();
    final galpon = _selectedGalpon!;
    final edad = int.tryParse(_edadController.text.trim()) ?? -1;
    if (edad < 0) return;

    setState(() => _isLoadingPlanSuggestions = true);
    final suggestions = storage.getPlanMatchSuggestions(
      granja: granja,
      campania: camp,
      galpon: galpon,
      edad: edad,
    );
    setState(() {
      _planSuggestions = suggestions;
      _isLoadingPlanSuggestions = false;
      if (_selectedPlanId != null &&
          _selectedPlanId!.isNotEmpty &&
          suggestions.any((e) => e['idCronograma']?.toString() == _selectedPlanId)) {
        return;
      }
      _selectedPlanId = null;
      _selectedPlanLabel = '';
    });
  }

  String _buildPlanLabel(Map<String, dynamic> row) {
    final fecha = row['fechaEjecucion']?.toString() ?? '';
    final edad = row['edad']?.toString() ?? '0';
    final tol = row['tolerancia']?.toString() ?? '0';
    final cod = row['codPrograma']?.toString() ?? '';
    final isExact = row['isExact'] == true;
    final tipo = isExact ? 'Exacto' : 'Tolerancia';
    if (isExact) {
      return 'Edad $edad (tol $tol) | $tipo';
    }
    return 'Edad $edad (tol $tol) | $fecha | $cod | $tipo';
  }

  Future<void> _showRegistroPlanificacionEventualDialog() async {
    final storage = context.read<StorageService>();
    final programs = <Map<String, String>>[];
    final seen = <String>{};
    for (final c in storage.getPlanMatchCandidatesLocal()) {
      final cod = c['codPrograma']?.toString() ?? '';
      if (!cod.startsWith('NC')) continue;
      final nom = c['nomPrograma']?.toString() ?? cod;
      if (cod.isEmpty || seen.contains(cod)) continue;
      seen.add(cod);
      programs.add({'codPrograma': cod, 'nomPrograma': nom});
    }
    if (programs.isEmpty) {
      programs.add({'codPrograma': 'NC', 'nomPrograma': 'NECROPSIAS'});
    }

    final initialGranja = (_selectedCenco ?? '').length >= 3
        ? _selectedCenco!.substring(0, 3)
        : (_selectedCenco ?? '');

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PlanEventualDialogWidget(
        programs: programs,
        initialGranja: initialGranja,
        initialCampania: _campController.text.trim(),
        initialGalpon: _selectedGalpon ?? '',
        initialEdad: _edadController.text.trim(),
        storage: storage,
        selectedDate: _selectedDate,
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedPlanId = result['localPlanId'] as String;
        _selectedPlanLabel = result['label'] as String;
      });
      showSuccessToast(
        context,
        'Registro eventual guardado correctamente.',
      );
    }
  }

  Future<void> _showPlanSuggestionsDialog() async {
    await _refreshPlanSuggestions();
    if (!mounted) return;
    if (_planSuggestions.isEmpty) {
      await _showRegistroPlanificacionEventualDialog();
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: ListView.separated(
            itemCount: _planSuggestions.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final row = _planSuggestions[index];
              return ListTile(
                title: Text(_buildPlanLabel(row)),
                subtitle: Text(row['nomPrograma']?.toString() ?? ''),
                onTap: () => Navigator.pop(context, row),
              );
            },
          ),
        ),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedPlanId = selected['idCronograma']?.toString();
        _selectedPlanLabel = _buildPlanLabel(selected);
      });
    }
  }

  Widget _buildPlanificacionField() {
    final bool sinSugerencias =
        !_isLoadingPlanSuggestions &&
        _planSuggestions.isEmpty &&
        _selectedCenco != null &&
        _selectedGalpon != null &&
        _campController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _showPlanSuggestionsDialog,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: 'Relacionar con planificación',
              floatingLabelBehavior: FloatingLabelBehavior.always,
              labelStyle: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: AppColors.cardBackground,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              suffixIcon: _isLoadingPlanSuggestions
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              _selectedPlanLabel.isNotEmpty
                  ? _selectedPlanLabel
                  : (_planSuggestions.isEmpty ? 'Sin sugerencias' : 'Seleccione'),
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        /*if (sinSugerencias)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 13, color: Colors.orange.shade700),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'No se encontró planificación para los datos ingresados. '
                    'Regístrela previamente usando "Registro eventual".',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          */

      ],
    );
  }

  Future<void> _loadGalpones(
    String cencoCode, {
    bool preserveSelected = false,
  }) async {
    final storage = context.read<StorageService>();

    // Cargar siempre desde storage local
    final galponesPorCenco = storage.getGalponesPorCencoLocal();
    final galponesData = galponesPorCenco[cencoCode] ?? [];

    List<Galpon> galpones;

    if (galponesData.isNotEmpty) {
      // Convertir a objetos Galpon
      galpones = galponesData
          .map(
            (g) => Galpon(
              tcencos: cencoCode,
              tcodint: g['tcodint']?.toString() ?? '',
              fecIngMin: g['fec_ing_min']?.toString(),
            ),
          )
          .toList();

      debugPrint(
        '✅ Galpones cargados desde storage local para CENCO $cencoCode: ${galpones.length}',
      );
    } else {
      // Si no hay datos locales, mostrar mensaje pero no cargar desde API
      debugPrint(
        '⚠️ No hay galpones en storage local para CENCO $cencoCode. Por favor, descargue los galpones desde el menú.',
      );
      galpones = [];
    }

    setState(() {
      final previousGalpon = _selectedGalpon;
      _galpones = galpones;
      // Si preserveSelected es true y el galpón anterior existe en la nueva lista, mantenerlo
      if (preserveSelected && previousGalpon != null) {
        final galponExists = galpones.any((g) => g.tcodint == previousGalpon);
        if (galponExists) {
          _selectedGalpon = previousGalpon;
        } else {
          _selectedGalpon = null;
        }
      } else {
        _selectedGalpon = null; // Resetear galpón al cambiar cenco
      }
    });
  }

  Future<void> _pickImage(String section, ImageSource source, int index) async {
    // Cerrar teclado antes de abrir cámara/galería
    _hideKeyboard();
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: source);

    if (pickedFile != null) {
      // Copiar a directorio temporal para que el path sea accesible (cámara y galería)
      // así addEvidencias y api_service pueden leer/comprimir el archivo correctamente
      XFile imageFile = pickedFile;
      try {
        final bytes = await pickedFile.readAsBytes();
        final tempDir = await getTemporaryDirectory();
        final ext = path.extension(pickedFile.path).isEmpty
            ? '.jpg'
            : path.extension(pickedFile.path);
        final tempPath = path.join(
          tempDir.path,
          'necropcia_${DateTime.now().millisecondsSinceEpoch}_$index$ext',
        );
        final tempFile = File(tempPath);
        await tempFile.writeAsBytes(bytes);
        imageFile = XFile(tempPath);
      } catch (e) {
        debugPrint('No se pudo copiar imagen a temp, usando original: $e');
      }

      // Preguntar si quiere editar la imagen
      final shouldEdit = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('¿Editar imagen?'),
          content: const Text(
            '¿Deseas agregar texto o realizar ediciones a la imagen?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No, usar tal cual'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Sí, editar'),
            ),
          ],
        ),
      );

      if (shouldEdit == true) {
        // Abrir el editor; si el usuario descarta, volver a mostrar el diálogo para que decida de nuevo
        XFile? currentFile = imageFile;
        bool done = false;
        while (!done && mounted) {
          final result = await _showImageEditor(section, index, currentFile);
          if (result != null && mounted) {
            setState(() {
              if (_inmunologicoImages.containsKey(section)) {
                final currentList = List<XFile?>.from(
                  _inmunologicoImages[section]!,
                );
                if (index >= 0 && index < currentList.length) {
                  currentList[index] = result;
                  _inmunologicoImages[section] = currentList;
                }
              } else if (_digestivoImages.containsKey(section)) {
                final currentList = List<XFile?>.from(
                  _digestivoImages[section]!,
                );
                if (index >= 0 && index < currentList.length) {
                  currentList[index] = result;
                  _digestivoImages[section] = currentList;
                }
              } else if (_respiratorioImages.containsKey(section)) {
                final currentList = List<XFile?>.from(
                  _respiratorioImages[section]!,
                );
                if (index >= 0 && index < currentList.length) {
                  currentList[index] = result;
                  _respiratorioImages[section] = currentList;
                }
              } else if (_fisicaImages.containsKey(section)) {
                final currentList = List<XFile?>.from(_fisicaImages[section]!);
                if (index >= 0 && index < currentList.length) {
                  currentList[index] = result;
                  _fisicaImages[section] = currentList;
                }
              }
            });
            done = true;
          } else {
            // Usuario descartó: volver a preguntar para no perder la imagen
            final again = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('¿Editar imagen?'),
                content: const Text(
                  '¿Deseas agregar texto o realizar ediciones a la imagen?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No, usar tal cual'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    child: const Text('Sí, editar'),
                  ),
                ],
              ),
            );
            if (again != true || !mounted) {
              done = true;
              if (again == false && mounted) {
                setState(() {
                  if (_inmunologicoImages.containsKey(section)) {
                    final currentList = List<XFile?>.from(
                      _inmunologicoImages[section]!,
                    );
                    if (index >= 0 && index < currentList.length) {
                      currentList[index] = currentFile;
                      _inmunologicoImages[section] = currentList;
                    }
                  } else if (_digestivoImages.containsKey(section)) {
                    final currentList = List<XFile?>.from(
                      _digestivoImages[section]!,
                    );
                    if (index >= 0 && index < currentList.length) {
                      currentList[index] = currentFile;
                      _digestivoImages[section] = currentList;
                    }
                  } else if (_respiratorioImages.containsKey(section)) {
                    final currentList = List<XFile?>.from(
                      _respiratorioImages[section]!,
                    );
                    if (index >= 0 && index < currentList.length) {
                      currentList[index] = currentFile;
                      _respiratorioImages[section] = currentList;
                    }
                  } else if (_fisicaImages.containsKey(section)) {
                    final currentList = List<XFile?>.from(
                      _fisicaImages[section]!,
                    );
                    if (index >= 0 && index < currentList.length) {
                      currentList[index] = currentFile;
                      _fisicaImages[section] = currentList;
                    }
                  }
                });
              }
            }
          }
        }
      } else {
        // Guardar la imagen sin editar
        setState(() {
          if (_inmunologicoImages.containsKey(section)) {
            final currentList = List<XFile?>.from(
              _inmunologicoImages[section]!,
            );
            if (index >= 0 && index < currentList.length) {
              currentList[index] = imageFile;
              _inmunologicoImages[section] = currentList;
            }
          } else if (_digestivoImages.containsKey(section)) {
            final currentList = List<XFile?>.from(_digestivoImages[section]!);
            if (index >= 0 && index < currentList.length) {
              currentList[index] = imageFile;
              _digestivoImages[section] = currentList;
            }
          } else if (_respiratorioImages.containsKey(section)) {
            final currentList = List<XFile?>.from(
              _respiratorioImages[section]!,
            );
            if (index >= 0 && index < currentList.length) {
              currentList[index] = imageFile;
              _respiratorioImages[section] = currentList;
            }
          } else if (_fisicaImages.containsKey(section)) {
            final currentList = List<XFile?>.from(_fisicaImages[section]!);
            if (index >= 0 && index < currentList.length) {
              currentList[index] = imageFile;
              _fisicaImages[section] = currentList;
            }
          }
        });
      }
    }
  }

  void _removeImage(String section, int index) {
    _registerStartTimeIfNeeded();
    setState(() {
      if (_inmunologicoImages.containsKey(section)) {
        final currentList = List<XFile?>.from(_inmunologicoImages[section]!);
        if (index >= 0 && index < currentList.length) {
          currentList[index] = null;
          _inmunologicoImages[section] = currentList;
        }
      } else if (_digestivoImages.containsKey(section)) {
        final currentList = List<XFile?>.from(_digestivoImages[section]!);
        if (index >= 0 && index < currentList.length) {
          currentList[index] = null;
          _digestivoImages[section] = currentList;
        }
      } else if (_respiratorioImages.containsKey(section)) {
        final currentList = List<XFile?>.from(_respiratorioImages[section]!);
        if (index >= 0 && index < currentList.length) {
          currentList[index] = null;
          _respiratorioImages[section] = currentList;
        }
      } else if (_fisicaImages.containsKey(section)) {
        final currentList = List<XFile?>.from(_fisicaImages[section]!);
        if (index >= 0 && index < currentList.length) {
          currentList[index] = null;
          _fisicaImages[section] = currentList;
        }
      }
    });
  }

  int _calculatePercentage(List<bool> selections) {
    // Cada checkbox representa 20% (5 checkboxes = 100%)
    return selections.where((e) => e).length * 20;
  }

  @override
  Widget build(BuildContext context) {
    // Si está en modo edición, no mostrar AppBar ni drawer (el modal tiene su propio AppBar)
    if (widget.isEditing) {
      return Container(
        color: AppColors.background,
        child: SafeArea(
          bottom: true,
          child: Form(
            key: _formKey,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SizedBox(
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildCabeceraScrollable(context),
            // TABS - margen horizontal 8 para que el contenedor se vea más ancho
            Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    decoration: BoxDecoration(
                      color: AppColors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        // Indicador de posición de pestañas - Se oculta cuando el teclado está visible
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          height:
                              MediaQuery.of(context).viewInsets.bottom > 0
                                  ? 0
                                  : null,
                          child:
                              MediaQuery.of(context).viewInsets.bottom > 0
                                  ? const SizedBox.shrink()
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.05),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: AppColors.primary.withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(Icons.swipe_rounded, size: 16,
                                                  color: AppColors.iconAccent.withOpacity(0.9)),
                                              const SizedBox(width: 6),
                                              AnimatedBuilder(
                                                animation: _tabController,
                                                builder: (context, child) {
                                                  return Text(
                                                    'Pestaña ${_tabController.index + 1} de ${_tabController.length}',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: AppColors.iconAccent.withOpacity(0.9),
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: List.generate(5, (index) {
                                              final isActive = _tabController.index == index;
                                              return Container(
                                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                                width: isActive ? 24 : 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: isActive
                                                      ? AppColors.iconAccent
                                                      : AppColors.iconAccent.withOpacity(0.3),
                                                  borderRadius: BorderRadius.circular(3),
                                                ),
                                              );
                                            }),
                                          ),
                                        ],
                                      ),
                                    ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          height: MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : null,
                          child: MediaQuery.of(context).viewInsets.bottom > 0
                              ? const SizedBox.shrink()
                              : Stack(
                                  children: [
                                    TabBar(
                                      controller: _tabController,
                                      labelColor: AppColors.iconAccent,
                                      unselectedLabelColor: AppColors.textMuted,
                                      indicatorColor: AppColors.iconAccent,
                                      indicatorWeight: 3,
                                      isScrollable: true,
                                      tabAlignment: TabAlignment.start,
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        height: 1.2,
                                        color: AppColors.iconAccent,
                                      ),
                                      unselectedLabelStyle: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                        fontSize: 11,
                                        height: 1.2,
                                      ),
                                      labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      tabs: [
                                        _buildMarqueeTab('Sistema Inmunológico', 0),
                                        _buildMarqueeTab('Sistema Digestivo', 1),
                                        _buildMarqueeTab('Sistema Respiratorio', 2),
                                        _buildMarqueeTab('Evaluación Física', 3),
                                        _buildMarqueeTab('Diag. Presuntivo', 4),
                                      ],
                                    ),
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 20,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                            colors: [
                                              AppColors.cardBackground,
                                              AppColors.cardBackground.withOpacity(0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 0,
                                      top: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 20,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.centerRight,
                                            end: Alignment.centerLeft,
                                            colors: [
                                              AppColors.cardBackground,
                                              AppColors.cardBackground.withOpacity(0),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ), // AnimatedContainer TabBar
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: [
                                    _buildExpandableSubsection(
                                      'INDICE BURSAL',
                                      _inmunologicoSubsectionsExpanded['INDICE BURSAL']!,
                                      (expanded) => setState(() => _inmunologicoSubsectionsExpanded['INDICE BURSAL'] = expanded),
                                      _inmunologicoData['INDICE BURSAL']!,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _inmunologicoData['INDICE BURSAL']![entry.key]![index] = value);
                                      },
                                      'INDICE BURSAL',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildExpandableSubsection(
                                      'MUCOSA DE LA BURSA',
                                      _inmunologicoSubsectionsExpanded['MUCOSA DE LA BURSA']!,
                                      (expanded) => setState(() => _inmunologicoSubsectionsExpanded['MUCOSA DE LA BURSA'] = expanded),
                                      _inmunologicoData['MUCOSA DE LA BURSA']!,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _inmunologicoData['MUCOSA DE LA BURSA']![entry.key]![index] = value);
                                      },
                                      'MUCOSA DE LA BURSA',
                                    ),
                                    const SizedBox(height: 12),
                                    _buildExpandableSubsection(
                                      'TIMOS',
                                      _inmunologicoSubsectionsExpanded['TIMOS']!,
                                      (expanded) => setState(() => _inmunologicoSubsectionsExpanded['TIMOS'] = expanded),
                                      _inmunologicoData['TIMOS']!,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _inmunologicoData['TIMOS']![entry.key]![index] = value);
                                      },
                                      'TIMOS',
                                    ),
                                  ],
                                ),
                              ),
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: _digestivoData.entries.map((sectionEntry) {
                                    return _buildExpandableSubsection(
                                      sectionEntry.key,
                                      _digestivoSubsectionsExpanded[sectionEntry.key] ?? true,
                                      (expanded) => setState(() => _digestivoSubsectionsExpanded[sectionEntry.key] = expanded),
                                      sectionEntry.value,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _digestivoData[sectionEntry.key]![entry.key]![index] = value);
                                      },
                                      sectionEntry.key,
                                    );
                                  }).toList(),
                                ),
                              ),
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: _respiratorioData.entries.map((sectionEntry) {
                                    return _buildExpandableSubsection(
                                      sectionEntry.key,
                                      _respiratorioSubsectionsExpanded[sectionEntry.key] ?? true,
                                      (expanded) => setState(() => _respiratorioSubsectionsExpanded[sectionEntry.key] = expanded),
                                      sectionEntry.value,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _respiratorioData[sectionEntry.key]![entry.key]![index] = value);
                                      },
                                      sectionEntry.key,
                                    );
                                  }).toList(),
                                ),
                              ),
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  children: _fisicaData.entries.map((sectionEntry) {
                                    return _buildExpandableSubsection(
                                      sectionEntry.key,
                                      _fisicaSubsectionsExpanded[sectionEntry.key] ?? true,
                                      (expanded) => setState(() => _fisicaSubsectionsExpanded[sectionEntry.key] = expanded),
                                      sectionEntry.value,
                                      (entry, index, value) {
                                        _registerStartTimeIfNeeded();
                                        setState(() => _fisicaData[sectionEntry.key]![entry.key]![index] = value);
                                      },
                                      sectionEntry.key,
                                    );
                                  }).toList(),
                                ),
                              ),
                              SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.primary.withOpacity(0.2),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.info_outline, color: AppColors.iconAccent, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Ingrese conclusiones preliminares basadas en las lesiones observadas durante la necropsia',
                                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                      controller: _diagnosticoPresuntivoController,
                                      maxLines: 10,
                                      minLines: 5,
                                      onChanged: (_) => _registerStartTimeIfNeeded(),
                                      decoration: InputDecoration(
                                        labelText: 'Diagnóstico Presuntivo',
                                        floatingLabelBehavior: FloatingLabelBehavior.always,
                                        labelStyle: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                        hintText: 'Ingrese las conclusiones preliminares...',
                                        hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 12),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                        filled: true,
                                        fillColor: AppColors.cardBackground,
                                        contentPadding: const EdgeInsets.all(16),
                                        suffixIcon: IconButton(
                                          icon: _buildMicIcon(size: 24),
                                          onPressed: () => _startListeningForController(_diagnosticoPresuntivoController),
                                          tooltip: _speechListening ? 'Detener dictado (pulsar de nuevo)' : 'Dictar por voz',
                                        ),
                                      ),
                                      style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        );
      },
    ),
          ),
        ),
      );
    } else {
      // Modo normal: Scaffold con AppBar y drawer (colores del tema para modo oscuro)
      return Scaffold(
        appBar: buildAppBar(
          context,
          'Registro de Necropsia',
          appIcon: Icons.assignment_rounded,
          rightIcon: Icons.save,
          rightIconColor: AppColors.iconAccent,
          onRightIconPressed: () => _saveRegistro(),
        ),
        drawer: const AppDrawer(),
        body: Container(
          color: AppColors.background,
          child: SafeArea(
            bottom: true,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera desplazable (Origen, GRI, granja, etc.)
                  _buildCabeceraScrollable(context),
                  // TABS - Ocupa el resto del espacio disponible
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        children: [
                        // Indicador de posición de pestañas - Se oculta cuando el teclado está visible
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            height: MediaQuery.of(context).viewInsets.bottom > 0
                                ? 0
                                : null,
                            child: MediaQuery.of(context).viewInsets.bottom > 0
                                ? const SizedBox.shrink()
                                : Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(
                                        0.05,
                                      ),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppColors.primary.withOpacity(
                                            0.2,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.swipe_rounded,
                                              size: 16,
                                              color: AppColors.iconAccent
                                                  .withOpacity(0.9),
                                            ),
                                            const SizedBox(width: 6),
                                            AnimatedBuilder(
                                              animation: _tabController,
                                              builder: (context, child) {
                                                final currentIndex =
                                                    _tabController.index;
                                                final totalTabs =
                                                    _tabController.length;
                                                return Text(
                                                  'Pestaña ${currentIndex + 1} de $totalTabs',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.iconAccent
                                                        .withOpacity(0.9),
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: List.generate(5, (index) {
                                            return AnimatedBuilder(
                                              animation: _tabController,
                                              builder: (context, child) {
                                                final isActive =
                                                    _tabController.index ==
                                                    index;
                                                return Container(
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 2,
                                                      ),
                                                  width: isActive ? 24 : 6,
                                                  height: 6,
                                                  decoration: BoxDecoration(
                                                    color: isActive
                                                        ? AppColors.iconAccent
                                                        : AppColors.iconAccent
                                                              .withOpacity(0.3),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          3,
                                                        ),
                                                  ),
                                                );
                                              },
                                            );
                                          }),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          // TabBar con gradiente en los bordes para indicar scroll - Se oculta cuando el teclado está visible
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            height: MediaQuery.of(context).viewInsets.bottom > 0
                                ? 0
                                : null,
                            child: MediaQuery.of(context).viewInsets.bottom > 0
                                ? const SizedBox.shrink()
                                : Stack(
                                    children: [
                                      TabBar(
                                        controller: _tabController,
                                        labelColor: AppColors.iconAccent,
                                        unselectedLabelColor:
                                            AppColors.textMuted,
                                        indicatorColor: AppColors.iconAccent,
                                        indicatorWeight: 3,
                                        isScrollable:
                                            true, // Permite scroll horizontal si es necesario
                                        tabAlignment: TabAlignment
                                            .start, // Alinea las tabs al inicio
                                        labelStyle: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          height: 1.2,
                                          color: AppColors.iconAccent,
                                        ),
                                        unselectedLabelStyle: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                          height: 1.2,
                                        ),
                                        labelPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 8,
                                            ),
                                        tabs: [
                                          _buildMarqueeTab(
                                            'Sistema Inmunológico',
                                            0,
                                          ),
                                          _buildMarqueeTab(
                                            'Sistema Digestivo',
                                            1,
                                          ),
                                          _buildMarqueeTab(
                                            'Sistema Respiratorio',
                                            2,
                                          ),
                                          _buildMarqueeTab(
                                            'Evaluación Física',
                                            3,
                                          ),
                                          _buildMarqueeTab(
                                            'Diag. Presuntivo',
                                            4,
                                          ),
                                        ],
                                      ),
                                      // Gradiente izquierdo (indica que hay más contenido a la izquierda)
                                      Positioned(
                                        left: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 20,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerLeft,
                                              end: Alignment.centerRight,
                                              colors: [
                                                AppColors.cardBackground,
                                                AppColors.cardBackground
                                                    .withOpacity(0),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Gradiente derecho (indica que hay más contenido a la derecha)
                                      Positioned(
                                        right: 0,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 20,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              begin: Alignment.centerRight,
                                              end: Alignment.centerLeft,
                                              colors: [
                                                AppColors.cardBackground,
                                                AppColors.cardBackground
                                                    .withOpacity(0),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                // Tab 1: SISTEMA INMUNOLÓGICO
                                SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    children: [
                                      _buildExpandableSubsection(
                                        'INDICE BURSAL',
                                        _inmunologicoSubsectionsExpanded['INDICE BURSAL']!,
                                        (expanded) {
                                          setState(() {
                                            _inmunologicoSubsectionsExpanded['INDICE BURSAL'] =
                                                expanded;
                                          });
                                        },
                                        _inmunologicoData['INDICE BURSAL']!,
                                        (entry, index, value) {
                                          _registerStartTimeIfNeeded();
                                          setState(() {
                                            _inmunologicoData['INDICE BURSAL']![entry
                                                    .key]![index] =
                                                value;
                                          });
                                        },
                                        'INDICE BURSAL',
                                      ),
                                      const SizedBox(height: 12),
                                      _buildExpandableSubsection(
                                        'MUCOSA DE LA BURSA',
                                        _inmunologicoSubsectionsExpanded['MUCOSA DE LA BURSA']!,
                                        (expanded) {
                                          setState(() {
                                            _inmunologicoSubsectionsExpanded['MUCOSA DE LA BURSA'] =
                                                expanded;
                                          });
                                        },
                                        _inmunologicoData['MUCOSA DE LA BURSA']!,
                                        (entry, index, value) {
                                          setState(() {
                                            _inmunologicoData['MUCOSA DE LA BURSA']![entry
                                                    .key]![index] =
                                                value;
                                          });
                                        },
                                        'MUCOSA DE LA BURSA',
                                      ),
                                      const SizedBox(height: 12),
                                      _buildExpandableSubsection(
                                        'TIMOS',
                                        _inmunologicoSubsectionsExpanded['TIMOS']!,
                                        (expanded) {
                                          setState(() {
                                            _inmunologicoSubsectionsExpanded['TIMOS'] =
                                                expanded;
                                          });
                                        },
                                        _inmunologicoData['TIMOS']!,
                                        (entry, index, value) {
                                          setState(() {
                                            _inmunologicoData['TIMOS']![entry
                                                    .key]![index] =
                                                value;
                                          });
                                        },
                                        'TIMOS',
                                      ),
                                    ],
                                  ),
                                ),
                                // Tab 2: SISTEMA DIGESTIVO
                                SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 16,
                                    bottom:
                                        16 +
                                        MediaQuery.of(
                                          context,
                                        ).viewInsets.bottom,
                                  ),
                                  child: Column(
                                    children: [
                                      ..._digestivoData.entries.map((
                                        sectionEntry,
                                      ) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: _buildExpandableSubsection(
                                            sectionEntry.key,
                                            _digestivoSubsectionsExpanded[sectionEntry
                                                    .key] ??
                                                false,
                                            (expanded) {
                                              setState(() {
                                                _digestivoSubsectionsExpanded[sectionEntry
                                                        .key] =
                                                    expanded;
                                              });
                                            },
                                            sectionEntry.value,
                                            (entry, index, value) {
                                              _registerStartTimeIfNeeded();
                                              setState(() {
                                                _digestivoData[sectionEntry
                                                        .key]![entry
                                                        .key]![index] =
                                                    value;
                                              });
                                            },
                                            sectionEntry.key,
                                            showObservationAndImage: true,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                // Tab 3: SISTEMA RESPIRATORIO
                                SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 16,
                                    bottom:
                                        16 +
                                        MediaQuery.of(
                                          context,
                                        ).viewInsets.bottom,
                                  ),
                                  child: Column(
                                    children: [
                                      ..._respiratorioData.entries.map((
                                        sectionEntry,
                                      ) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: _buildExpandableSubsection(
                                            sectionEntry.key,
                                            _respiratorioSubsectionsExpanded[sectionEntry
                                                    .key] ??
                                                false,
                                            (expanded) {
                                              setState(() {
                                                _respiratorioSubsectionsExpanded[sectionEntry
                                                        .key] =
                                                    expanded;
                                              });
                                            },
                                            sectionEntry.value,
                                            (entry, index, value) {
                                              _registerStartTimeIfNeeded();
                                              setState(() {
                                                _respiratorioData[sectionEntry
                                                        .key]![entry
                                                        .key]![index] =
                                                    value;
                                              });
                                            },
                                            sectionEntry.key,
                                            showObservationAndImage: true,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                // Tab 4: EVALUACIÓN FÍSICA
                                SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 16,
                                    bottom:
                                        16 +
                                        MediaQuery.of(
                                          context,
                                        ).viewInsets.bottom,
                                  ),
                                  child: Column(
                                    children: [
                                      ..._fisicaData.entries.map((
                                        sectionEntry,
                                      ) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 12,
                                          ),
                                          child: _buildExpandableSubsection(
                                            sectionEntry.key,
                                            _fisicaSubsectionsExpanded[sectionEntry
                                                    .key] ??
                                                false,
                                            (expanded) {
                                              setState(() {
                                                _fisicaSubsectionsExpanded[sectionEntry
                                                        .key] =
                                                    expanded;
                                              });
                                            },
                                            sectionEntry.value,
                                            (entry, index, value) {
                                              _registerStartTimeIfNeeded();
                                              setState(() {
                                                _fisicaData[sectionEntry
                                                        .key]![entry
                                                        .key]![index] =
                                                    value;
                                              });
                                            },
                                            sectionEntry.key,
                                            showObservationAndImage: true,
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                                // Tab 5: DIAGNÓSTICO PRESUNTIVO
                                SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    left: 16,
                                    right: 16,
                                    top: 16,
                                    bottom:
                                        16 +
                                        MediaQuery.of(
                                          context,
                                        ).viewInsets.bottom,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary.withOpacity(
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withOpacity(0.3),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.info_outline,
                                              color: AppColors.iconAccent,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Ingrese conclusiones preliminares basadas en las lesiones observadas durante la necropsia',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color:
                                                      AppColors.textSecondary,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      TextFormField(
                                        controller:
                                            _diagnosticoPresuntivoController,
                                        maxLines: 10,
                                        minLines: 5,
                                        decoration: InputDecoration(
                                          labelText: 'Diagnóstico Presuntivo',
                                          floatingLabelBehavior:
                                              FloatingLabelBehavior.always,
                                          labelStyle: TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 14,
                                          ),
                                          hintText:
                                              'Ingrese las conclusiones preliminares...',
                                          hintStyle: TextStyle(
                                            color: AppColors.textMuted,
                                            fontSize: 12,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          filled: true,
                                          fillColor: AppColors.cardBackground,
                                          contentPadding: const EdgeInsets.all(
                                            16,
                                          ),
                                          suffixIcon: IconButton(
                                            icon: _buildMicIcon(size: 24),
                                            onPressed: () =>
                                                _startListeningForController(
                                                  _diagnosticoPresuntivoController,
                                                ),
                                            tooltip: _speechListening
                                                ? 'Detener dictado (pulsar de nuevo)'
                                                : 'Dictar por voz',
                                          ),
                                        ),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
  }

  // Widget para Tab con mejor visibilidad usando solo texto en dos filas
  Widget _buildMarqueeTab(String text, int index) {
    // Dividir el texto en dos partes: "Sistema" y el resto
    final parts = text.split(' ');
    String firstLine = '';
    String secondLine = '';

    if (parts.length >= 2) {
      firstLine = parts[0]; // "Sistema" o "Evaluación"
      secondLine = parts.sublist(1).join(' '); // El resto
    } else {
      firstLine = text;
      secondLine = '';
    }

    return Tab(
      height: 55, // Altura suficiente para dos líneas
      child: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          final isSelected = _tabController.index == index;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  firstLine,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isSelected ? 11 : 10,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    height: 1.1,
                    letterSpacing: 0.1,
                    color: isSelected
                        ? AppColors.iconAccent
                        : AppColors.textMuted,
                  ),
                ),
                if (secondLine.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondLine,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: isSelected ? 11 : 10,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w600,
                      height: 1.1,
                      letterSpacing: 0.1,
                      color: isSelected
                          ? AppColors.iconAccent
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  // Widget para mostrar dropdown con buscador (versión compacta)
  Future<void> _showSearchableDropdown<T>({
    required String title,
    required List<T> items,
    required String Function(T) getLabel,
    required String? Function(T) getValue,
    required String? selectedValue,
    required Function(String?) onSelected,
    String Function(T)? getSubtitle,
  }) async {
    final searchController = TextEditingController();
    List<T> displayedItems = List.from(items);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12), // Menos radio
              ),
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(
                  maxHeight: 500,
                ), // Más corto
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // HEADER COMPACTO (sin color verde)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                        ),
                        border: Border(
                          bottom: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(
                              Icons.close,
                              color: Colors.grey.shade600,
                              size: 20,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // BUSCADOR COMPACTO
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 12,
                        right: 12,
                        top: 12,
                        bottom: 8,
                      ), // Menos padding
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Buscar...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                          ), // Ajustar ícono
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ), // Más compacto
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              10,
                            ), // Menos radio
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          filled: true,
                          fillColor: AppColors.cardBackground,
                          isDense: true, // Clave para altura reducida
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            displayedItems = items.where((item) {
                              final label = getLabel(item).toLowerCase();
                              final subtitle = getSubtitle != null
                                  ? getSubtitle(item).toLowerCase()
                                  : '';
                              final search = value.toLowerCase();
                              return label.contains(search) ||
                                  subtitle.contains(search);
                            }).toList();
                          });
                        },
                      ),
                    ),

                    // LISTA COMPACTA
                    Expanded(
                      child: displayedItems.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: Text(
                                  'No se encontraron resultados',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: displayedItems.length,
                              itemBuilder: (context, index) {
                                final item = displayedItems[index];
                                final value = getValue(item);
                                final isSelected = value == selectedValue;
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6, // Más compacto
                                  ),
                                  title: Text(
                                    getLabel(item),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.iconAccent
                                          : null,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: getSubtitle != null
                                      ? Text(
                                          getSubtitle(item),
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textMuted,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        )
                                      : null,
                                  selected: isSelected,
                                  selectedTileColor: AppColors.iconAccent
                                      .withOpacity(0.15)
                                      .withOpacity(0.08),
                                  onTap: () {
                                    onSelected(value);
                                    Navigator.pop(context);
                                  },
                                  visualDensity:
                                      VisualDensity.compact, // Más compacto
                                  dense: true,
                                  trailing: isSelected
                                      ? Icon(
                                          Icons.check,
                                          color: AppColors.iconAccent,
                                          size: 18,
                                        )
                                      : null,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExpandableSubsection(
    String title,
    bool isExpanded,
    Function(bool) onExpansionChanged,
    Map<String, List<bool>> data,
    Function(MapEntry<String, List<bool>> entry, int index, bool value)
    onCheckboxChanged,
    String sectionKey, {
    bool showObservationAndImage = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
            fontSize: 15,
          ),
        ),
        tilePadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        dense: true,
        visualDensity: VisualDensity.compact,
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        children: [
          ...data.entries.map((entry) {
            return _buildSublevelRowWithCheckboxes(
              title,
              entry.key,
              entry.value,
              (index, value) => onCheckboxChanged(entry, index, value),
            );
          }),
          if (showObservationAndImage) ...[
            const SizedBox(height: 8),
            _buildObservationField(sectionKey),
            const SizedBox(height: 8),
            _buildImagePicker(sectionKey),
          ],
        ],
      ),
    );
  }

  Widget _buildSublevelRowWithCheckboxes(
    String section,
    String label,
    List<bool> checkboxes,
    Function(int index, bool value) onChanged,
  ) {
    final percentage = _calculatePercentage(checkboxes);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Label con más espacio para mostrar el nombre completo
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                textAlign: TextAlign.left,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 5 Checkboxes que ocupan el espacio disponible
          Expanded(
            flex: 2,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return Expanded(
                  child: Transform.scale(
                    scale: 0.85,
                    child: Checkbox(
                      value: checkboxes[index],
                      onChanged: (value) => onChanged(index, value ?? false),
                      activeColor: AppColors.iconAccent,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 6),
          // Porcentaje con contenedor más pequeño
          Container(
            constraints: const BoxConstraints(minWidth: 40),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '$percentage%',
              style: TextStyle(
                color: AppColors.iconAccent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildObservationField(String section) {
    // Obtener el valor inicial según el nivel (para inicializar el controller si aún no existe)
    String initialValue = '';
    if (_inmunologicoObservaciones.containsKey(section)) {
      initialValue = _inmunologicoObservaciones[section] ?? '';
    } else if (_digestivoObservaciones.containsKey(section)) {
      initialValue = _digestivoObservaciones[section] ?? '';
    } else if (_respiratorioObservaciones.containsKey(section)) {
      initialValue = _respiratorioObservaciones[section] ?? '';
    } else if (_fisicaObservaciones.containsKey(section)) {
      initialValue = _fisicaObservaciones[section] ?? '';
    }

    final controller = _getObservationController(section, initialValue);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: TextFormField(
        key: ValueKey('obs_${_observationFieldKeySeed}_$section'),
        controller: controller,
        minLines: 3,
        maxLines: 8,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: InputDecoration(
          labelText: 'Observación',
          hintText: 'Escriba o dicte las observaciones…',
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: TextStyle(color: AppColors.textSecondary),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: AppColors.cardBackground,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          alignLabelWithHint: true,
          suffixIcon: IconButton(
            icon: _buildMicIcon(size: 22),
            onPressed: () => _startListeningForController(
              controller,
              onTextUpdated: (newText) {
                if (_inmunologicoObservaciones.containsKey(section)) {
                  _inmunologicoObservaciones[section] = newText;
                } else if (_digestivoObservaciones.containsKey(section)) {
                  _digestivoObservaciones[section] = newText;
                } else if (_respiratorioObservaciones.containsKey(section)) {
                  _respiratorioObservaciones[section] = newText;
                } else if (_fisicaObservaciones.containsKey(section)) {
                  _fisicaObservaciones[section] = newText;
                }
              },
            ),
            tooltip: _speechListening ? 'Detener dictado (pulsar de nuevo)' : 'Dictar por voz',
          ),
        ),
        onChanged: (value) {
          _registerStartTimeIfNeeded();
          setState(() {
            if (_inmunologicoObservaciones.containsKey(section)) {
              _inmunologicoObservaciones[section] = value;
            } else if (_digestivoObservaciones.containsKey(section)) {
              _digestivoObservaciones[section] = value;
            } else if (_respiratorioObservaciones.containsKey(section)) {
              _respiratorioObservaciones[section] = value;
            } else if (_fisicaObservaciones.containsKey(section)) {
              _fisicaObservaciones[section] = value;
            }
          });
        },
      ),
    );
  }

  TextEditingController _getObservationController(
    String section,
    String initialValue,
  ) {
    if (_observationControllers.containsKey(section)) {
      return _observationControllers[section]!;
    }
    final controller = TextEditingController(text: initialValue);
    _observationControllers[section] = controller;
    return controller;
  }

  void _setObservationControllerTextIfExists(String section, String value) {
    final controller = _observationControllers[section];
    if (controller == null) return;
    if (controller.text == value) return;
    controller.text = value;
  }

  void _hideKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  Future<void> _showImageSourceDialog(String section, int index) async {
    // Cerrar teclado antes de mostrar el diálogo (y antes de abrir cámara/galería)
    _hideKeyboard();
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: Theme.of(context).copyWith(
            dialogBackgroundColor: Colors.white,
            // Asegura que los textos se vean bien
            textTheme: Theme.of(
              context,
            ).textTheme.apply(bodyColor: Colors.black),
          ),
          child: AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Seleccionar imagen'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.camera_alt, color: AppColors.iconAccent),
                  title: const Text('Cámara'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),

                ListTile(
                  leading: Icon(
                    Icons.photo_library,
                    color: AppColors.iconAccent,
                  ),
                  title: const Text('Galería'),
                  onTap: () => Navigator.pop(context, ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source != null) {
      await _pickImage(section, source, index);
    }
  }

  // Mostrar editor de imagen; devuelve XFile si guardó, null si descartó
  Future<XFile?> _showImageEditor(
    String section,
    int index,
    XFile imageFile,
  ) async {
    _hideKeyboard();
    final result = await Navigator.push<XFile?>(
      context,
      MaterialPageRoute(
        builder: (context) => ImageEditorScreen(imageFile: imageFile),
      ),
    );
    return result;
  }

  Widget _buildImagePicker(String section) {
    List<XFile?> imageFiles = [null, null, null];
    if (_inmunologicoImages.containsKey(section)) {
      imageFiles = List<XFile?>.from(_inmunologicoImages[section]!);
    } else if (_digestivoImages.containsKey(section)) {
      imageFiles = List<XFile?>.from(_digestivoImages[section]!);
    } else if (_respiratorioImages.containsKey(section)) {
      imageFiles = List<XFile?>.from(_respiratorioImages[section]!);
    } else if (_fisicaImages.containsKey(section)) {
      imageFiles = List<XFile?>.from(_fisicaImages[section]!);
    }

          // Asegurar que siempre haya 3 elementos
    while (imageFiles.length < 3) {
      imageFiles.add(null);
    }

    return Row(
      children: List.generate(3, (index) {
        final imageFile = index < imageFiles.length ? imageFiles[index] : null;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < 2 ? 8 : 0),
            child: GestureDetector(
              onTap: () async {
                _registerStartTimeIfNeeded();
                _hideKeyboard();
                if (imageFile == null) {
                  _showImageSourceDialog(section, index);
                } else {
                  // Si ya hay una imagen, permitir editarla y actualizar miniatura al guardar
                  final result = await _showImageEditor(
                    section,
                    index,
                    imageFile,
                  );
                  if (result != null && mounted) {
                    setState(() {
                      if (_inmunologicoImages.containsKey(section)) {
                        final currentList = List<XFile?>.from(
                          _inmunologicoImages[section]!,
                        );
                        if (index >= 0 && index < currentList.length) {
                          currentList[index] = result;
                          _inmunologicoImages[section] = currentList;
                        }
                      } else if (_digestivoImages.containsKey(section)) {
                        final currentList = List<XFile?>.from(
                          _digestivoImages[section]!,
                        );
                        if (index >= 0 && index < currentList.length) {
                          currentList[index] = result;
                          _digestivoImages[section] = currentList;
                        }
                      } else if (_respiratorioImages.containsKey(section)) {
                        final currentList = List<XFile?>.from(
                          _respiratorioImages[section]!,
                        );
                        if (index >= 0 && index < currentList.length) {
                          currentList[index] = result;
                          _respiratorioImages[section] = currentList;
                        }
                      } else if (_fisicaImages.containsKey(section)) {
                        final currentList = List<XFile?>.from(
                          _fisicaImages[section]!,
                        );
                        if (index >= 0 && index < currentList.length) {
                          currentList[index] = result;
                          _fisicaImages[section] = currentList;
                        }
                      }
                    });
                  }
                }
              },
              child: Container(
                height: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.cardBackground,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CustomPaint(
                    painter: _DashedBorderPainter(
                      color: AppColors.iconAccent,
                      strokeWidth: 2,
                      dashWidth: 6,
                      dashSpace: 4,
                    ),
                    child: Container(
                      height: double.infinity,
                      width: double.infinity,
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.cardBackground,
                      ),
                      child: imageFile != null
                          ? Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(imageFile.path),
                                    width: double.infinity,
                                    height: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: double.infinity,
                                        height: double.infinity,
                                        color: AppColors.surface,
                                        child: Icon(
                                          Icons.image,
                                          size: 30,
                                          color: AppColors.iconAccent,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                // Icono de lápiz: indica que la imagen puede editarse
                                Positioned(
                                  bottom: 4,
                                  left: 4,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.edit_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: GestureDetector(
                                    onTap: () => _removeImage(section, index),
                                    child: Container(
                                      width: 24,
                                      height: 24,
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Center(
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.iconAccent,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  // Recopilar todos los datos del formulario
  Map<String, dynamic> _collectData() {
    const uuid = Uuid();

    // Si está editando, usar el tuuid y numreg existentes, sino generar nuevos
    String? tuuid;
    String? numreg;
    // Fecha/hora de registro (solo se setea al crear; en edición se preserva)
    String? tdate;
    String? ttime;
    String? diareg;
    if (widget.isEditing && widget.initialData != null) {
      tuuid = widget.initialData!['tuuid']?.toString();
      numreg = widget.initialData!['numreg']?.toString();
      // Preservar fecha/hora de registro original si existe
      tdate = widget.initialData!['tdate']?.toString();
      ttime = widget.initialData!['ttime']?.toString();
      diareg = widget.initialData!['diareg']?.toString();
    }

    // Si no está editando o no hay numreg, generar uno nuevo: HHMMSS
    if (numreg == null || numreg.isEmpty) {
      final now = DateTime.now();
      final horas = now.hour.toString().padLeft(2, '0');
      final minutos = now.minute.toString().padLeft(2, '0');
      final segundos = now.second.toString().padLeft(2, '0');
      numreg = '$horas$minutos$segundos';
    }

    if (tuuid == null || tuuid.isEmpty) {
      tuuid = uuid.v4();
      debugPrint(
        '📝 _collectData - Generado nuevo tuuid para record principal: $tuuid',
      );
    } else {
      debugPrint(
        '📝 _collectData - Preservando tuuid del record principal: $tuuid',
      );
    }

    // Obtener datos del CENCOS seleccionado (GRS)
    String? codigoGranja;
    String? tcencos;
    String? campania;
    String? edad;

    if (_esGrs && _selectedCenco != null && _cencos.isNotEmpty) {
      final selectedCenco = _cencos.firstWhere(
        (c) => c.codigo == _selectedCenco,
        orElse: () => _cencos.first,
      );
      codigoGranja = selectedCenco.codigo;
      tcencos = selectedCenco.nombre;
      campania = _campController.text;
      edad = _edadController.text;
    } else if (_esOrigenExtTp) {
      codigoGranja = _codigoOrigenExtController.text.trim();
      campania = '000';
      edad = _edadController.text.trim();
    }

    final fectraIso = _selectedDate.toIso8601String().split('T')[0];
    final cabMap = NecropsiasOrigen.cabeceraFromForm(
      origen: _origen,
      codigoGranja: codigoGranja,
      campania: campania,
      galpon: _selectedGalpon,
      edad: edad,
      fectra: fectraIso,
      tcencos: tcencos,
      codigoOrigenExt: _codigoOrigenExtController.text.trim(),
    );

    // === CABECERA ===
    final Map<String, dynamic> cabecera = <String, dynamic>{
      ...cabMap,
      'fectra': fectraIso,
      'galpon': _esGrs ? (_selectedGalpon ?? '') : cabMap['galpon'] ?? '0',
      'numreg': numreg,
      'codigoNecropsia': _esOrigenExtTp
          ? _codigoNecropsiaController.text.trim()
          : '',
      'tcencos': tcencos ?? cabMap['tcencos'] ?? '',
      'diagnostico_presuntivo': _diagnosticoPresuntivoController.text,
      'planId': _selectedPlanId ?? '',
      'planLabel': _selectedPlanLabel,
    };

    if (_esGrs &&
        _griSeleccion != null &&
        _griSeleccion!.trim().isNotEmpty) {
      cabecera['gri_seleccion'] = _griSeleccion!.trim();
      final parts = _griSeleccion!.split('|');
      if (parts.length == 3) {
        cabecera['gri_tdoc'] = parts[0];
        cabecera['gri_tserie'] = parts[1];
        cabecera['gri_tnumfac'] = parts[2];
      }
    }

    // Agregar hora de inicio y fin solo para nuevos registros (no ediciones)
    if (!widget.isEditing) {
      final nowReg = DateTime.now();
      cabecera['tdate'] =
          '${nowReg.year}-${nowReg.month.toString().padLeft(2, '0')}-${nowReg.day.toString().padLeft(2, '0')}';
      cabecera['diareg'] = cabecera['tdate']; // mismo día de registro
      cabecera['ttime'] =
          '${nowReg.hour.toString().padLeft(2, '0')}:${nowReg.minute.toString().padLeft(2, '0')}:${nowReg.second.toString().padLeft(2, '0')}';

      // Asegurar que la hora de inicio esté registrada
      if (_horaInicioRegistro == null) {
        _horaInicioRegistro = DateTime.now();
      }

      // Hora de inicio (datetime completo, formato YYYY-MM-DD HH:MM:SS)
      if (_horaInicioRegistro != null) {
        final horaInicio = _horaInicioRegistro!;
        cabecera['tfecreghorainicio'] =
            '${horaInicio.year}-${horaInicio.month.toString().padLeft(2, '0')}-${horaInicio.day.toString().padLeft(2, '0')} ${horaInicio.hour.toString().padLeft(2, '0')}:${horaInicio.minute.toString().padLeft(2, '0')}:${horaInicio.second.toString().padLeft(2, '0')}';
      }

      // Hora de fin (datetime completo, formato YYYY-MM-DD HH:MM:SS)
      final horaFin = DateTime.now();
      cabecera['tfecreghorafin'] =
          '${horaFin.year}-${horaFin.month.toString().padLeft(2, '0')}-${horaFin.day.toString().padLeft(2, '0')} ${horaFin.hour.toString().padLeft(2, '0')}:${horaFin.minute.toString().padLeft(2, '0')}:${horaFin.second.toString().padLeft(2, '0')}';

      debugPrint(
        '🕐 Registro de horas - Inicio: ${cabecera['tfecreghorainicio']}, Fin: ${cabecera['tfecreghorafin']}',
      );
    } else if (widget.isEditing && widget.initialData != null) {
      // Preservar fecha/hora de registro original si existe
      if (tdate != null && tdate.isNotEmpty) cabecera['tdate'] = tdate;
      if (diareg != null && diareg.isNotEmpty) cabecera['diareg'] = diareg;
      if (ttime != null && ttime.isNotEmpty) cabecera['ttime'] = ttime;

      // Preservar las horas originales si está editando
      if (widget.initialData!['tfecreghorainicio'] != null) {
        cabecera['tfecreghorainicio'] =
            widget.initialData!['tfecreghorainicio'];
      }
      if (widget.initialData!['tfecreghorafin'] != null) {
        cabecera['tfecreghorafin'] = widget.initialData!['tfecreghorafin'];
      }
    }

    // === REGISTROS ===
    final registros = <Map<String, dynamic>>[];

    if (widget.isEditing && widget.initialData != null) {
      // === MODO EDICIÓN: Preservar TODOS los registros originales ===
      final registrosOriginales =
          widget.initialData!['registros'] as List<dynamic>? ?? [];

      // Crear un mapa de los registros modificados por el usuario
      // Clave: "sistema|nivel|parametro", Valor: datos del formulario
      final Map<String, Map<String, dynamic>> registrosModificados = {};

      void agregarRegistrosModificados(
        String sistema,
        Map<String, Map<String, List<bool>>> data,
        Map<String, String> observaciones,
      ) {
        data.forEach((nivel, opciones) {
          opciones.forEach((parametro, checkboxes) {
            final porcentajeTotal = _calculatePercentage(checkboxes);
            final aves = checkboxes.map((checked) => checked ? 20 : 0).toList();

            // Asegurar que siempre haya 5 valores
            while (aves.length < 5) {
              aves.add(0);
            }

            final clave = '$sistema|$nivel|$parametro';
            registrosModificados[clave] = {
              'tporcentaje1': aves[0],
              'tporcentaje2': aves[1],
              'tporcentaje3': aves[2],
              'tporcentaje4': aves[3],
              'tporcentaje5': aves[4],
              'tporcentajetotal': porcentajeTotal,
              'tobservacion': observaciones[nivel] ?? '',
            };
          });
        });
      }

      // Recopilar todos los registros modificados por el usuario
      agregarRegistrosModificados(
        'SISTEMA INMUNOLOGICO',
        _inmunologicoData,
        _inmunologicoObservaciones,
      );
      agregarRegistrosModificados(
        'SISTEMA DIGESTIVO',
        _digestivoData,
        _digestivoObservaciones,
      );
      agregarRegistrosModificados(
        'SISTEMA RESPIRATORIO',
        _respiratorioData,
        _respiratorioObservaciones,
      );
      agregarRegistrosModificados(
        'EVALUACION FISICA',
        _fisicaData,
        _fisicaObservaciones,
      );

      debugPrint(
        '📋 _collectData - Registros modificados por usuario: ${registrosModificados.length}',
      );

      // Procesar TODOS los registros originales
      for (var regOriginal in registrosOriginales) {
        final sistemaOrig = regOriginal['tsistema']?.toString() ?? '';
        final nivelOrig = regOriginal['tnivel']?.toString() ?? '';
        final parametroOrig = regOriginal['tparametro']?.toString() ?? '';
        final tuuidOrig = regOriginal['tuuid']?.toString() ?? '';

        if (sistemaOrig.isEmpty ||
            nivelOrig.isEmpty ||
            parametroOrig.isEmpty ||
            tuuidOrig.isEmpty) {
          continue; // Saltar registros inválidos
        }

        final clave = '$sistemaOrig|$nivelOrig|$parametroOrig';
        final registroModificado = registrosModificados[clave];

        // Si el usuario modificó este registro, usar los valores del formulario
        // Si no, mantener los valores originales
        if (registroModificado != null) {
          // Registro modificado: usar valores del formulario pero preservar UUID original
          registros.add({
            'tuuid': tuuidOrig, // SIEMPRE preservar UUID original
            'tsistema': sistemaOrig,
            'tnivel': nivelOrig,
            'tparametro': parametroOrig,
            'tporcentaje1': registroModificado['tporcentaje1'],
            'tporcentaje2': registroModificado['tporcentaje2'],
            'tporcentaje3': registroModificado['tporcentaje3'],
            'tporcentaje4': registroModificado['tporcentaje4'],
            'tporcentaje5': registroModificado['tporcentaje5'],
            'tporcentajetotal': registroModificado['tporcentajetotal'],
            'tobservacion': registroModificado['tobservacion'],
          });
        } else {
          // Registro NO modificado: mantener todos los valores originales
          registros.add({
            'tuuid': tuuidOrig,
            'tsistema': sistemaOrig,
            'tnivel': nivelOrig,
            'tparametro': parametroOrig,
            'tporcentaje1': regOriginal['tporcentaje1'] ?? 0,
            'tporcentaje2': regOriginal['tporcentaje2'] ?? 0,
            'tporcentaje3': regOriginal['tporcentaje3'] ?? 0,
            'tporcentaje4': regOriginal['tporcentaje4'] ?? 0,
            'tporcentaje5': regOriginal['tporcentaje5'] ?? 0,
            'tporcentajetotal': regOriginal['tporcentajetotal'] ?? 0,
            'tobservacion': regOriginal['tobservacion'] ?? '',
          });
        }
      }

      debugPrint(
        '📋 _collectData - Total registros preservados: ${registros.length}',
      );
    } else {
      // === MODO CREACIÓN: Generar nuevos registros ===
      // Función auxiliar para agregar registros de un sistema
      void addRegistros(
        String sistema,
        Map<String, Map<String, List<bool>>> data,
        Map<String, String> observaciones,
      ) {
        data.forEach((nivel, opciones) {
          opciones.forEach((parametro, checkboxes) {
            final porcentajeTotal = _calculatePercentage(checkboxes);
            final aves = checkboxes.map((checked) => checked ? 20 : 0).toList();

            // Asegurar que siempre haya 5 valores
            while (aves.length < 5) {
              aves.add(0);
            }

            registros.add({
              'tuuid': uuid.v4(), // Generar nuevo UUID para nuevo registro
              'tsistema': sistema,
              'tnivel': nivel,
              'tparametro': parametro,
              'tporcentaje1': aves[0],
              'tporcentaje2': aves[1],
              'tporcentaje3': aves[2],
              'tporcentaje4': aves[3],
              'tporcentaje5': aves[4],
              'tporcentajetotal': porcentajeTotal,
              'tobservacion': observaciones[nivel] ?? '',
            });
          });
        });
      }

      // Agregar registros de cada sistema
      addRegistros(
        'SISTEMA INMUNOLOGICO',
        _inmunologicoData,
        _inmunologicoObservaciones,
      );
      addRegistros(
        'SISTEMA DIGESTIVO',
        _digestivoData,
        _digestivoObservaciones,
      );
      addRegistros(
        'SISTEMA RESPIRATORIO',
        _respiratorioData,
        _respiratorioObservaciones,
      );
      addRegistros('EVALUACION FISICA', _fisicaData, _fisicaObservaciones);
    }

    // === EVIDENCIAS (imágenes) ===
    // Agrupar imágenes por nivel (puede haber hasta 3 por nivel)
    final evidenciasPorNivel = <String, List<Map<String, dynamic>>>{};

    // Si está editando, primero cargar las evidencias originales para preservarlas
    if (widget.isEditing && widget.initialData != null) {
      final evidenciasOriginales =
          widget.initialData!['evidencias_completas']
              as Map<String, dynamic>? ??
          {};
      debugPrint(
        '📸 _collectData - Preservando evidencias originales: ${evidenciasOriginales.length} niveles',
      );

      // Copiar todas las evidencias originales primero
      evidenciasOriginales.forEach((key, value) {
        if (value is List) {
          // Convertir a lista de Map si es necesario
          final listaImagenes = value.map((item) {
            if (item is Map<String, dynamic>) {
              return Map<String, dynamic>.from(item);
            } else {
              return {'path': item.toString()};
            }
          }).toList();
          evidenciasPorNivel[key] = listaImagenes;
          debugPrint(
            '   📸 Preservado nivel $key con ${listaImagenes.length} imágenes',
          );
        }
      });
    } else {
      debugPrint(
        '📸 _collectData - Nuevo registro, evidenciasPorNivel inicialmente vacío',
      );
    }

    void addEvidencias(Map<String, List<XFile?>> images, String sistema) {
      debugPrint(
        '📸 addEvidencias - Procesando sistema: $sistema con ${images.length} niveles',
      );

      images.forEach((nivel, imageFiles) {
        final nivelKey = '${sistema}_$nivel';
        final imagenesNivel = <Map<String, dynamic>>[];

        // Verificar si hay imágenes nuevas seleccionadas por el usuario
        bool tieneImagenesNuevas = false;
        int imagenesValidas = 0;

        for (var imageFile in imageFiles) {
          if (imageFile != null) {
            // Verificar si el archivo existe localmente
            final file = File(imageFile.path);
            if (file.existsSync()) {
              imagenesNivel.add({
                'path': imageFile.path,
                'name': imageFile.name,
                'sistema': sistema,
                'nivel': nivel,
              });
              tieneImagenesNuevas = true;
              imagenesValidas++;
              debugPrint('     ✓ Imagen válida agregada: ${imageFile.path}');
            } else {
              debugPrint('     ✗ Archivo no existe: ${imageFile.path}');
            }
          }
        }

        // CRÍTICO: Para nuevos registros, siempre agregar las imágenes si existen
        // Para ediciones, reemplazar solo si hay imágenes nuevas
        if (tieneImagenesNuevas) {
          evidenciasPorNivel[nivelKey] = imagenesNivel;
          debugPrint(
            '   📸 Nivel $nivelKey: ${imagenesValidas} imágenes agregadas (total en nivel: ${imagenesNivel.length})',
          );
        } else if (!widget.isEditing &&
            !evidenciasPorNivel.containsKey(nivelKey)) {
          // Para nuevos registros sin imágenes, agregar lista vacía
          evidenciasPorNivel[nivelKey] = imagenesNivel;
          debugPrint('   📸 Nivel $nivelKey: Sin imágenes (nuevo registro)');
        } else if (widget.isEditing &&
            !evidenciasPorNivel.containsKey(nivelKey)) {
          // Para ediciones sin imágenes nuevas y sin originales, agregar lista vacía
          evidenciasPorNivel[nivelKey] = imagenesNivel;
          debugPrint(
            '   📸 Nivel $nivelKey: Sin imágenes nuevas, sin originales',
          );
        } else if (widget.isEditing) {
          debugPrint(
            '   📸 Nivel $nivelKey: Sin cambios, manteniendo ${evidenciasPorNivel[nivelKey]?.length ?? 0} imágenes originales',
          );
        }
      });
    }

    addEvidencias(_inmunologicoImages, 'INMUNOLOGICO');
    addEvidencias(_digestivoImages, 'DIGESTIVO');
    addEvidencias(_respiratorioImages, 'RESPIRATORIO');
    addEvidencias(_fisicaImages, 'FISICA');

    // Log final de evidenciasPorNivel
    debugPrint('📸 _collectData - Resumen final de evidenciasPorNivel:');
    int totalImagenes = 0;
    evidenciasPorNivel.forEach((key, imagenes) {
      totalImagenes += imagenes.length;
      debugPrint('   - $key: ${imagenes.length} imágenes');
      if (imagenes.isNotEmpty) {
        for (var img in imagenes) {
          debugPrint('     → ${img['path']}');
        }
      }
    });
    debugPrint('   Total imágenes en evidenciasPorNivel: $totalImagenes');

    // Convertir a formato plano para metadata (una clave por nivel con lista de imágenes)
    // IMPORTANTE: Incluir todos los niveles, incluso los vacíos, para que el servidor sepa qué procesar
    final evidencias = <String, Map<String, dynamic>>{};
    evidenciasPorNivel.forEach((key, imagenes) {
      // Obtener sistema y nivel del primer elemento o de la clave
      String sistema = '';
      String nivel = '';

      if (imagenes.isNotEmpty) {
        sistema = imagenes.first['sistema'] ?? '';
        nivel = imagenes.first['nivel'] ?? '';
      } else {
        // Si no hay imágenes, extraer de la clave (formato: "SISTEMA_NIVEL")
        final parts = key.split('_');
        if (parts.length >= 2) {
          sistema = parts[0];
          nivel = parts.sublist(1).join('_');
        }
      }

      // Incluir en metadata incluso si está vacío (cantidad 0 indica que se deben limpiar)
      evidencias[key] = {
        'sistema': sistema,
        'nivel': nivel,
        'cantidad': imagenes
            .length, // Puede ser 0 si el usuario eliminó todas las imágenes
      };
    });

    final result = {
      ...cabecera,
      'tuuid': tuuid, // SIEMPRE incluir el tuuid del record principal
      'registros': registros,
      'evidencias': evidencias,
      'evidencias_completas': evidenciasPorNivel, // Para envío de archivos
    };

    // Log final del resultado
    final evidenciasCompletasFinal =
        result['evidencias_completas'] as Map<String, dynamic>? ?? {};
    debugPrint(
      '📸 _collectData - evidencias_completas en result: ${evidenciasCompletasFinal.length} niveles',
    );
    if (evidenciasCompletasFinal.isEmpty) {
      debugPrint('   ⚠️ ADVERTENCIA: evidencias_completas está vacío!');
    } else {
      int totalFinal = 0;
      evidenciasCompletasFinal.forEach((key, value) {
        if (value is List) {
          totalFinal += value.length;
        }
      });
      debugPrint('   Total imágenes finales: $totalFinal');
    }

    return result;
  }

  // Función auxiliar para formatear fechas a dd/mm/yyyy para mostrar en el campo
  String _formatDateForDisplay(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();
    return '$day/$month/$year';
  }

  // Función auxiliar para formatear fechas a dd/mm/yyyy
  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'No especificado';
    try {
      // Intentar parsear formato ISO (yyyy-mm-dd) o cualquier formato
      final date = DateTime.parse(dateString);
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year.toString();
      return '$day/$month/$year';
    } catch (e) {
      return dateString; // Si no se puede parsear, retornar original
    }
  }

  String _formatGriResumen(dynamic griSeleccion) {
    final raw = griSeleccion?.toString().trim() ?? '';
    if (raw.isEmpty) return '—';
    final parts = raw.split('|');
    if (parts.length >= 3) {
      return '${parts[1]}-${parts[2]}';
    }
    return raw;
  }

  // Función auxiliar para formatear CENCOS (mostrar solo hasta antes de 'C=')
  String _formatCenco(String? cencoString) {
    if (cencoString == null || cencoString.isEmpty) return 'No especificado';
    final indexC = cencoString.indexOf(' C=');
    if (indexC != -1) {
      return cencoString.substring(0, indexC).trim();
    }
    return cencoString;
  }

  // Mostrar modal de resumen a pantalla completa con deslizamiento
  Future<void> _showSummaryModal(Map<String, dynamic> data) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 1.0,
        minChildSize: 0.5,
        maxChildSize: 1.0,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              // Header con indicador de deslizamiento
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Indicador de deslizamiento
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFFC107,
                            ).withOpacity(0.15), // Dorado suave
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.description_outlined,
                            color: AppColors.iconAccent,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Resumen de Necropsia',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Contenido con scroll
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // CABECERA en columnas
                      _buildSummarySection(
                        'Información General',
                        Icons.info_outline,
                        [
                          if ((data['codigoNecropsia']?.toString().trim() ?? '')
                              .isNotEmpty)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _buildSummaryItemCompact(
                                'Código necropsia',
                                data['codigoNecropsia'].toString(),
                              ),
                            ),
                          if ((data['codigoNecropsia']?.toString().trim() ?? '')
                              .isNotEmpty)
                            const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _buildSummaryItemCompact(
                              'Origen',
                              data['origen']?.toString() ?? 'GRS',
                            ),
                          ),
                          if ((data['gri_seleccion']?.toString().trim() ?? '')
                              .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: _buildSummaryItemCompact(
                                'GRI',
                                _formatGriResumen(data['gri_seleccion']),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: _buildSummaryItemCompact(
                              'Fecha Necropsia',
                              _formatDate(data['fectra']),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Segunda fila: Granja y Campaña
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryItemCompact(
                                  'Granja',
                                  _formatCenco(data['tcencos']),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSummaryItemCompact(
                                  'Campaña',
                                  data['campania'] ?? '',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Tercera fila: Galpón y Edad
                          Row(
                            children: [
                              Expanded(
                                child: _buildSummaryItemCompact(
                                  'Galpón',
                                  data['galpon'] ?? '',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildSummaryItemCompact(
                                  'Edad',
                                  data['edad'] ?? '',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // REGISTROS POR SISTEMA
                      ..._buildRegistrosSummary(
                        data['registros'] as List<Map<String, dynamic>>,
                        data['evidencias_completas'] as Map<String, dynamic>? ??
                            {},
                      ),
                      const SizedBox(height: 16),
                      // DIAGNÓSTICO PRESUNTIVO AL FINAL
                      _buildSummarySection(
                        'Diagnóstico Presuntivo',
                        Icons.medical_information_outlined,
                        [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Text(
                              (data['diagnostico_presuntivo']?.toString() ?? '')
                                      .isEmpty
                                  ? 'No especificado'
                                  : data['diagnostico_presuntivo']
                                            ?.toString() ??
                                        '',
                              style: TextStyle(
                                fontSize: 13,
                                color:
                                    (data['diagnostico_presuntivo']
                                                ?.toString() ??
                                            '')
                                        .isEmpty
                                    ? AppColors.textMuted
                                    : AppColors.textPrimary,
                                fontWeight: FontWeight.w500,
                                fontStyle:
                                    (data['diagnostico_presuntivo']
                                                ?.toString() ??
                                            '')
                                        .isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              // Botones fijos en la parte inferior
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: const Text(
                          'Cancelar',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () {

                          _confirmSave(data);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Confirmar y Guardar',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummarySection(
    String title,
    IconData icon,
    List<Widget> children,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppColors.iconAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItemCompact(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Text(
            value.isEmpty ? 'No especificado' : value,
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildRegistrosSummary(
    List<Map<String, dynamic>> registros,
    Map<String, dynamic> evidenciasCompletas,
  ) {
      // Agrupar registros por sistema
    final Map<String, List<Map<String, dynamic>>> registrosPorSistema = {};

    for (var registro in registros) {
      final sistema = registro['tsistema'] as String;
      if (!registrosPorSistema.containsKey(sistema)) {
        registrosPorSistema[sistema] = [];
      }
      registrosPorSistema[sistema]!.add(registro);
    }

    return registrosPorSistema.entries.map((entry) {
      final sistema = entry.key;
      final registrosSistema = entry.value;

      // Agrupar por nivel dentro del sistema
      final Map<String, List<Map<String, dynamic>>> registrosPorNivel = {};
      for (var registro in registrosSistema) {
        final nivel = registro['tnivel'] as String;
        if (!registrosPorNivel.containsKey(nivel)) {
          registrosPorNivel[nivel] = [];
        }
        registrosPorNivel[nivel]!.add(registro);
      }

      return _buildSummarySection(sistema, Icons.description_outlined, [
        ...registrosPorNivel.entries.map((nivelEntry) {
          final nivel = nivelEntry.key;
          final registrosNivel = nivelEntry.value;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primary.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nivel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 8),
                // Mostrar parámetros en columnas (2 columnas)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 8) / 2;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: registrosNivel.map((registro) {
                        final parametro = registro['tparametro'] as String;
                        final porcentaje = registro['tporcentajetotal'] as int;

                        return SizedBox(
                          width: itemWidth,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    parametro,
                                    style: const TextStyle(fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '$porcentaje%',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                // Mostrar observación
                Builder(
                  builder: (context) {
                    final observacion =
                        registrosNivel.first['tobservacion'] as String? ?? '';
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.note_outlined,
                                size: 14,
                                color: AppColors.iconAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Observación:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.primary.withOpacity(0.2),
                              ),
                            ),
                            child: observacion.isNotEmpty
                                ? Text(
                                    observacion,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                      height: 1.4,
                                    ),
                                  )
                                : Text(
                                    'Sin observación',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                // Mostrar miniaturas de imágenes si existen
                Builder(
                  builder: (context) {
                    // Construir la clave igual que en _collectData
                    // En _collectData se usa: '${sistema}_$nivel' donde sistema es 'INMUNOLOGICO', 'DIGESTIVO', etc.
                    String sistemaKey = sistema.toUpperCase();
                    // Remover "SISTEMA " si existe
                    if (sistemaKey.startsWith('SISTEMA ')) {
                      sistemaKey = sistemaKey.substring(8);
                    }
                    sistemaKey = sistemaKey.replaceAll(' ', '_');
                    final nivelKey = '${sistemaKey}_$nivel';
                    final imagenesNivel =
                        evidenciasCompletas[nivelKey] as List<dynamic>? ?? [];

                    if (imagenesNivel.isEmpty) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Imágenes adjuntas:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: imagenesNivel.map((imagenData) {
                              if (imagenData is Map<String, dynamic>) {
                                final imagePath =
                                    imagenData['path'] as String? ?? '';
                                if (imagePath.isNotEmpty) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.file(
                                      File(imagePath),
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return Container(
                                              width: 60,
                                              height: 60,
                                              color: AppColors.surface,
                                              child: const Icon(
                                                Icons.image,
                                                size: 20,
                                              ),
                                            );
                                          },
                                    ),
                                  );
                                }
                              }
                              return const SizedBox.shrink();
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        }),
      ]);
    }).toList();
  }

  // Confirmar y guardar
  Future<void> _confirmSave(Map<String, dynamic> data) async {
    // Cerrar primero el modal de resumen
    Navigator.of(context).pop();

    final closeDialog = showChickenLoadingDialog(
      context,
      widget.isEditing
          ? 'Actualizando evaluación...'
          : 'Guardando evaluación...',
    );

    try {
      final storage = context.read<StorageService>();

      // Agregar información del usuario y dispositivo
      data['tuser'] = storage.getUserCodeSync() ?? 'app_movil';
      data['tidandroid'] = await storage.getDeviceId() ?? 'app_movil';

      // SIMPLIFICADO: Usar una única bandera guardado_backend
      // Si guardado_backend == true, el registro ya existe en el backend usar actualizar_necropsia_movil.php
      // Si guardado_backend == false o no existe, el registro es nuevo usar guardar_necropsia_movil.php
      if (widget.isEditing && widget.initialData != null) {
        // CRÍTICO: Leer guardado_backend directamente desde storage para asegurar que tenemos el valor más actualizado
        // El initialData puede estar desactualizado si el registro fue sincronizado después de cargar la pantalla
        final allRecords = storage.getAllRecords(AppStrings.formType1);
        final currentRecord = allRecords.firstWhere(
          (r) => r['tuuid']?.toString() == data['tuuid']?.toString(),
          orElse: () => {},
        );

        // Usar el valor de storage si existe, sino usar el de initialData
        final guardadoBackendFromStorage = currentRecord.isNotEmpty
            ? currentRecord['guardado_backend']
            : widget.initialData!['guardado_backend'];

        final guardadoBackend =
            guardadoBackendFromStorage ??
            widget.initialData!['guardado_backend'];
        final guardadoBackendBool =
            guardadoBackend == true ||
            guardadoBackend == 'true' ||
            guardadoBackend == 1;

        debugPrint('🔍 _confirmSave - Verificando guardado_backend:');
        debugPrint(
          '   - guardado_backend desde storage: $guardadoBackendFromStorage',
        );
        debugPrint(
          '   - guardado_backend desde initialData: ${widget.initialData!['guardado_backend']}',
        );
        debugPrint('   - guardado_backend final usado: $guardadoBackend');
        debugPrint('   - guardado_backendBool: $guardadoBackendBool');

        if (guardadoBackendBool) {
          // El registro ya existe en el backend, preservar la bandera
          data['guardado_backend'] = true;
          data['synced'] =
              false; // Marcar como no sincronizado porque fue editado
          debugPrint(
            '✅ Registro editado (guardado_backend=true) → actualizar_necropsia_movil.php',
          );
        } else {
          // El registro nunca fue enviado al backend
          data['guardado_backend'] = false;
          data['synced'] = false;
          debugPrint(
            '📝 Registro editado (guardado_backend=false) → guardar_necropsia_movil.php',
          );
        }
      } else {
        // Nuevo registro: nunca ha sido enviado al backend
        data['guardado_backend'] = false;
        data['synced'] = false;
        debugPrint(
          '📝 Nuevo registro (guardado_backend=false) → guardar_necropsia_movil.php',
        );
      }

      // Verificar que evidencias_completas esté presente antes de guardar
      final evidenciasCompletas = data['evidencias_completas'];
      if (evidenciasCompletas != null && evidenciasCompletas is Map) {
        debugPrint(
          '📸 _confirmSave - evidencias_completas presente: ${evidenciasCompletas.length} niveles',
        );
      } else {
        debugPrint(
          '⚠️ _confirmSave - evidencias_completas NO presente o vacío',
        );
      }

      // Guardar o actualizar localmente
      if (widget.isEditing) {
        await storage.updateRecord(AppStrings.formType1, data);
        debugPrint(
          '✓ Registro actualizado en storage (tuuid: ${data['tuuid']})',
        );
      } else {
        await storage.saveForm(AppStrings.formType1, data);
        debugPrint('✓ Registro guardado en storage (tuuid: ${data['tuuid']})');
      }

      closeDialog();

      final codigoMsg = (data['codigoNecropsia']?.toString().trim() ?? '');
      final msgOk = widget.isEditing
          ? 'Evaluación actualizada correctamente'
          : (codigoMsg.isNotEmpty
              ? 'Evaluación guardada. Código: $codigoMsg'
              : 'Evaluación guardada correctamente');
      showSuccessToast(context, msgOk);

      if (mounted) {
        if (widget.isEditing) {
          Navigator.of(context).pop(data);
        } else {
          _clearForm();
        }
      }
    } catch (e) {
      closeDialog();
      showErrorToast(context, 'Error al guardar: ${e.toString()}');
    }
  }

  Future<void> _saveRegistro() async {
    if (_fechaController.text.isEmpty) {
      showErrorToast(context, 'Selecciona una fecha');
      return;
    }

    if (_esOrigenExtTp) {
      if (_codigoOrigenExtController.text.trim().isEmpty) {
        showErrorToast(context, 'Ingrese el código de origen');
        return;
      }
    } else {
      if (_selectedCenco == null) {
        showErrorToast(context, 'Selecciona una granja');
        return;
      }
      if (_selectedGalpon == null) {
        showErrorToast(context, 'Selecciona un Galpón');
        return;
      }
      if (_griSeleccion == null || _griSeleccion!.trim().isEmpty) {
        showErrorToast(context, 'Debe seleccionar una GRI (origen GRS)');
        return;
      }

      // Regla: no permitir guardar necropsia GRS sin planificación asociada.
      if (_selectedPlanId == null || _selectedPlanId!.trim().isEmpty) {
        showErrorToast(
          context,
          _planSuggestions.isEmpty
              ? 'Registre una planificación eventual antes de guardar. Toque el campo "Relacionar con planificación".'
              : 'Debe seleccionar una planificación antes de guardar. Toque el campo "Relacionar con planificación".',
        );
        return;
      }
    }

    // Cerrar el teclado antes de mostrar el resumen
    _hideKeyboard();

    // Esperar un momento para que el teclado se cierre completamente
    await Future.delayed(const Duration(milliseconds: 100));

    // Recopilar datos y mostrar resumen (solo si todos los campos están validados)
    final data = _collectData();
    _showSummaryModal(data);
  }

  // Método público para guardar desde fuera
  Future<void> saveForm() async {
    await _saveRegistro();
  }

  void _clearForm() {
    setState(() {
      // IMPORTANTE: resetear el Form primero para que no re-escriba valores antiguos en los controllers
      _formKey.currentState?.reset();

      _observationFieldKeySeed++;
      for (final c in _observationControllers.values) {
        c.dispose();
      }
      _observationControllers.clear();

      // Limpiar selecciones
      _selectedCenco = null;
      _selectedGalpon = null;
      _selectedPlanId = null;
      _selectedPlanLabel = '';
      _planSuggestions = [];
      _galpones = [];
      _origen = OrigenNecropsia.grs;
      _griSeleccion = null;
      _griOpciones = [];
      _cargandoGri = false;

      // Limpiar campos de texto
      _campController.clear();
      _edadController.clear();
      _codigoOrigenExtController.clear();
      _diagnosticoPresuntivoController.clear();
      _selectedDate = DateTime.now();
      _fechaController.text = _formatDateForDisplay(_selectedDate);

      // Asegurar que CAMP y Edad queden vacíos tras limpiar (por si algún async intentara reescribirlos)
      _campController.text = '';
      _edadController.text = '';

      // Reiniciar hora de inicio para el próximo registro
      _horaInicioRegistro = DateTime.now();

      _codigoNecropsiaController.clear();

      // Reinicializar TODOS los datos de checkboxes desde cero
      // Inmunológico
      _inmunologicoData = {
        'INDICE BURSAL': {
          'Normal': [false, false, false, false, false],
          'Atrofia': [false, false, false, false, false],
          'Severa Atrofia': [false, false, false, false, false],
        },
        'MUCOSA DE LA BURSA': {
          'Normal': [false, false, false, false, false],
          'Petequias': [false, false, false, false, false],
          'Hemorragia': [false, false, false, false, false],
        },
        'TIMOS': {
          'Normal': [false, false, false, false, false],
          'Atrofiados': [false, false, false, false, false],
          'Aspecto Normal': [false, false, false, false, false],
          'Congestionado': [false, false, false, false, false],
        },
      };

      // Limpiar observaciones inmunológico
      _inmunologicoObservaciones = {
        'INDICE BURSAL': '',
        'MUCOSA DE LA BURSA': '',
        'TIMOS': '',
      };

      // Limpiar imágenes inmunológico
      _inmunologicoImages = {
        'INDICE BURSAL': [null, null, null],
        'MUCOSA DE LA BURSA': [null, null, null],
        'TIMOS': [null, null, null],
      };

      // Colapsar todas las secciones
      _inmunologicoSubsectionsExpanded = {
        'INDICE BURSAL': false,
        'MUCOSA DE LA BURSA': false,
        'TIMOS': false,
      };

      _initializeDigestivoData();
      _initializeRespiratorioData();
      _initializeFisicaData();
    });
    _loadCodigoNecropsiaPreview();
  }
}

/// Pinta un borde punteado (líneas discontinuas) alrededor del hijo.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  _DashedBorderPainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashWidth = 6,
    this.dashSpace = 4,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    const radius = 10.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(radius),
    );
    _drawDashedRRect(canvas, rrect, paint);
  }

  void _drawDashedRRect(Canvas canvas, RRect rrect, Paint paint) {
    final path = Path()..addRRect(rrect);
    final pathMetrics = path.computeMetrics();
    for (final metric in pathMetrics) {
      double distance = 0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        final extractPath = metric.extractPath(distance, end);
        canvas.drawPath(extractPath, paint);
        distance = end + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PlanEventualDialogWidget extends StatefulWidget {
  const _PlanEventualDialogWidget({
    required this.programs,
    required this.initialGranja,
    required this.initialCampania,
    required this.initialGalpon,
    required this.initialEdad,
    required this.storage,
    required this.selectedDate,
  });

  final List<Map<String, String>> programs;
  final String initialGranja;
  final String initialCampania;
  final String initialGalpon;
  final String initialEdad;
  final StorageService storage;
  final DateTime selectedDate;

  @override
  State<_PlanEventualDialogWidget> createState() =>
      _PlanEventualDialogWidgetState();
}

class _PlanEventualDialogWidgetState extends State<_PlanEventualDialogWidget> {
  late String selCodPrograma;
  late String selNomPrograma;
  late String selGranja;
  late String selCampania;
  late String selGalpon;
  late String selEdad;
  late final TextEditingController obsController;

  @override
  void initState() {
    super.initState();
    selCodPrograma = widget.programs.first['codPrograma']!;
    selNomPrograma = widget.programs.first['nomPrograma']!;
    selGranja = widget.initialGranja;
    selCampania = widget.initialCampania;
    selGalpon = widget.initialGalpon;
    selEdad = widget.initialEdad;
    obsController = TextEditingController();
  }

  @override
  void dispose() {
    obsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('Registro Planificacion Eventual'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: selCodPrograma,
                decoration: const InputDecoration(labelText: 'Programa'),
                items: widget.programs
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p['codPrograma'],
                        child: Text(
                          '${p['codPrograma']} - ${p['nomPrograma']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                selectedItemBuilder: (context) => widget.programs
                    .map(
                      (p) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${p['codPrograma']} - ${p['nomPrograma']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  final row = widget.programs.firstWhere(
                    (e) => e['codPrograma'] == v,
                    orElse: () => {'codPrograma': v, 'nomPrograma': v},
                  );
                  setState(() {
                    selCodPrograma = v;
                    selNomPrograma = row['nomPrograma'] ?? v;
                  });
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selGranja,
                decoration: const InputDecoration(labelText: 'Granja'),
                items: [
                  DropdownMenuItem(value: selGranja, child: Text(selGranja)),
                ],
                onChanged: (v) => setState(() => selGranja = v ?? selGranja),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selCampania,
                decoration: const InputDecoration(labelText: 'Campaña'),
                items: [
                  DropdownMenuItem(
                    value: selCampania,
                    child: Text(selCampania),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => selCampania = v ?? selCampania),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selGalpon,
                decoration: const InputDecoration(labelText: 'Galpón'),
                items: [
                  DropdownMenuItem(value: selGalpon, child: Text(selGalpon)),
                ],
                onChanged: (v) => setState(() => selGalpon = v ?? selGalpon),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: selEdad.isEmpty ? '0' : selEdad,
                decoration: const InputDecoration(labelText: 'Edad'),
                items: [
                  DropdownMenuItem(
                    value: selEdad.isEmpty ? '0' : selEdad,
                    child: Text(selEdad.isEmpty ? '0' : selEdad),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => selEdad = (v ?? selEdad).trim()),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: obsController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () async {
            final localPlanId =
                'EVT_LOCAL_${DateTime.now().millisecondsSinceEpoch}';
            final fecha =
                '${widget.selectedDate.year}-${widget.selectedDate.month.toString().padLeft(2, '0')}-${widget.selectedDate.day.toString().padLeft(2, '0')}';
            final eventual = {
              'localPlanId': localPlanId,
              'codPrograma': selCodPrograma,
              'nomPrograma': selNomPrograma,
              'granja': selGranja,
              'campania': selCampania,
              'galpon': selGalpon,
              'edad': int.tryParse(selEdad) ?? 0,
              'fecha': fecha,
              'observaciones': obsController.text.trim(),
              'synced': false,
              'createdAt': DateTime.now().toIso8601String(),
            };
            await widget.storage.savePlanEventualLocal(eventual);
            await widget.storage.addLocalPlanCandidate({
              'idCronograma': localPlanId,
              'granja': selGranja,
              'campania': selCampania,
              'galpon': selGalpon,
              'edad': int.tryParse(selEdad) ?? 0,
              'tolerancia': 1,
              'codPrograma': selCodPrograma,
              'nomPrograma': selNomPrograma,
              'fechaEjecucion': fecha,
              'numCronograma': 0,
              'isExact': true,
            });
            if (context.mounted) {
              Navigator.pop(context, {
                'localPlanId': localPlanId,
                'label': '$selGranja|$selCampania|$selGalpon|$selEdad',
              });
            }
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
