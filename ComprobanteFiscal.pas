﻿{* *****************************************************************************
  PROYECTO FACTURACION ELECTRONICA
  Copyright (C) 2010 - Bambu Code SA de CV - Ing. Luis Carrasco

  Esta clase representa un Comprobante Fiscal Digital en su Version 2.0 asi como
  los metodos para generarla.

  Este archivo pertenece al proyecto de codigo abierto de Bambu Code:
  http://bambucode.com/codigoabierto

  La licencia de este codigo fuente se encuentra en:
  http://github.com/bambucode/tfacturaelectronica/blob/master/LICENCIA
  ***************************************************************************** *}
unit ComprobanteFiscal;

interface

uses FacturaTipos, FeCFDv2, SysUtils, dialogs,
  // Unidades especificas de manejo de XML:
  XmlDom, XMLIntf, MsXmlDom, XMLDoc, DocComprobanteFiscal,
  {$IFDEF VER220}
    CodeSiteLogging,
  {$ENDIF}
  XSLProd;

type

  // Excepciones que pueden ser generadas
  EFECertificadoNoExisteException = class(Exception);
  EFECertificadoNoVigente =  class(Exception);
  EFEFolioFueraDeRango = class(Exception);

  /// <summary>Representa la estructura de comprobante fiscal digital (ver2.0) y sus elementos
  /// definidos de acuerdo al XSD del SAT. Esta pensado para ser extendido en las versiones
  /// posteriores que el SAT publique (ver3.0, ver4.0, etc.).
  /// Se encarga de validar y formatear todos los datos de la factura que le sean proporcionados
  /// </summary>
  TFEComprobanteFiscal = class(TDocumentoComprobanteFiscal)
{$IFDEF VERSION_DE_PRUEBA}
  public
{$ELSE}
  private
{$ENDIF}
    // Variables internas
    fDocumentoXML: TXMLDocument;
    fXmlComprobante: IFEXMLComprobante;

    // Propiedades exclusivas del comprobante digital:
    fCadenaOriginalCalculada: TStringCadenaOriginal;
    fSelloDigitalCalculado: String;
    fCertificado: TFECertificado;
    fCertificadoTexto: WideString;
    fBloqueFolios: TFEBloqueFolios;

    // Opciones de configuracion
    _CADENA_PAGO_UNA_EXHIBICION: String;
    _CADENA_PAGO_PARCIALIDADES: String;
    fDesglosarTotalesImpuestos: Boolean;
    bIncluirCertificadoEnXML: Boolean;

    procedure LlenarComprobante;
    procedure setCertificado(Certificado: TFECertificado);
    function getCadenaOriginal(): TStringCadenaOriginal;
    function getSelloDigital(): String;
    procedure setBloqueFolios(Bloque: TFEBloqueFolios);
    procedure ValidarQueFolioEsteEnRango;
    procedure AsignarCondicionesDePago;
    procedure AsignarEmisor;
    procedure AsignarReceptor;
    procedure AsignarContenidoCertificado;
    procedure AsignarConceptos;
    procedure AsignarImpuestosRetenidos;
    procedure AsignarImpuestosTrasladados;
    procedure AsignarDatosFolios;
    procedure AsignarFolio;
    procedure AsignarFormaDePago;
    procedure AsignarSubtotal;
    procedure AsignarTotal;
    procedure AsignarDescuentos;
    procedure AsignarMetodoDePago;
    procedure AsignarTipoComprobante;
    procedure AsignarExpedidoEn;
    procedure AsignarTotalesImpuestos;
    procedure AsignarFechaGeneracion;
  protected
    function getXML(): WideString; virtual;
    procedure setXML(Valor: WideString); virtual;
{$IFDEF VERSION_DE_PRUEBA}
  public
    _USAR_HORA_REAL : Boolean;
{$ELSE}
  protected
{$ENDIF}
  public
    const VERSION = '2'; // Version del CFD que implementa este código

    constructor Create();
    destructor Destroy(); override;
    procedure Cancelar();

    // Propiedades especificas al comprobante electronico
    property BloqueFolios: TFEBloqueFolios read fBloqueFolios write setBloqueFolios;
    property XML: WideString read getXML write setXML;
    property CadenaOriginal: TStringCadenaOriginal read getCadenaOriginal;
    property SelloDigital: String read getSelloDigital;
    property CertificadoTexto : WideString read fCertificadoTexto write fCertificadoTexto;
    property Certificado: TFECertificado read fCertificado write setCertificado;
    property DesglosarTotalesImpuestos: Boolean read fDesglosarTotalesImpuestos write fDesglosarTotalesImpuestos;
    property IncluirCertificadoEnXml: Boolean read bIncluirCertificadoEnXML write bIncluirCertificadoEnXML;
    
    /// <summary>Guarda una copia del XML en el archivo indicado</summary>
    /// <param name="ArchivoFacturaXML">Ruta completa con nombre de archivo en el que se
    /// almacenara el XML del comprobante</param>
    procedure GuardarEnArchivo(sArchivoDestino: String);
  end;
  
implementation

uses FacturaReglamentacion, ClaseOpenSSL, StrUtils, SelloDigital,
  OpenSSLUtils, Classes, CadenaOriginal;

// Al crear el objeto, comenzamos a "llenar" el XML interno
constructor TFEComprobanteFiscal.Create();
begin
  inherited Create;
  _CADENA_PAGO_UNA_EXHIBICION := 'Pago en una sola exhibición';
  _CADENA_PAGO_PARCIALIDADES := 'En parcialidades';

  {$IFDEF VERSION_DE_PRUEBA}
    _USAR_HORA_REAL := False;
  {$ENDIF}

  // Establecemos como default que SI queremos incluir el certificado en el XML
  // ya que presenta la ventaja de poder validar el comprobante con solo el archivo
  // XML.
  bIncluirCertificadoEnXML := True;
  fDesglosarTotalesImpuestos := True;
  fCadenaOriginalCalculada:='';
  fSelloDigitalCalculado:='';

  // Creamos el objeto XML
  fDocumentoXML := TXMLDocument.Create(nil);
  fDocumentoXML.Active := True;

  // Obtenemos el elemento "Comprobante" para llenar sus datos...
  fXmlComprobante := GetComprobante(fDocumentoXML);
  // De acuerdo a los articulos 29 y 29-A del CFF - Referencia: Revista "IDC Factura electronica" (Sept/2010) - Pag 49
  fXmlComprobante.SetAttribute('xmlns:xsi', 'http://www.w3.org/2001/XMLSchema-instance');
  fXmlComprobante.SetAttribute('xsi:schemaLocation',
    'http://www.sat.gob.mx/cfd/2 http://www.sat.gob.mx/sitio_internet/cfd/2/cfdv2.xsd');
  fXmlComprobante.Version := '2.0';

  fDocumentoXML.Version := '1.0';
  fDocumentoXML.Encoding := 'UTF-8';
end;

destructor TFEComprobanteFiscal.Destroy();
begin
  // Al ser una interface el objeto TXMLDocument se libera automaticamente por Delphi al dejar de ser usado
  // aunque para asegurarnos hacemos lo siguiente:
  fXmlComprobante := nil;
  inherited;
end;


procedure TFEComprobanteFiscal.AsignarCondicionesDePago;
begin
    if Trim(inherited CondicionesDePago) <> '' then
      fXmlComprobante.CondicionesDePago := TFEReglamentacion.ComoCadena(inherited CondicionesDePago);
end;

procedure TFEComprobanteFiscal.AsignarDescuentos;
begin
  fXmlComprobante.Descuento := TFEReglamentacion.ComoMoneda(inherited DescuentoMonto);
  if Trim(inherited DescuentoMotivo) <> '' then
    fXmlComprobante.MotivoDescuento := TFEReglamentacion.ComoCadena(inherited DescuentoMotivo);
end;

function TFEComprobanteFiscal.getCadenaOriginal(): TStringCadenaOriginal;
var
  CadenaOriginal : TCadenaOriginal;
begin
    if FacturaGenerada = True then
    begin
        Result:=fCadenaOriginalCalculada;
    end else
    begin
        try
            CadenaOriginal := TCadenaOriginal.Create(fXmlComprobante, fDesglosarTotalesImpuestos);
            fCadenaOriginalCalculada:=CadenaOriginal.Calcular;
            Result:=fCadenaOriginalCalculada;
        finally
            FreeAndNil(CadenaOriginal);
        end;
    end;
end;

// 1. Datos de quien la expide (Emisor) (Art. 29-A, Fraccion I)
procedure TFEComprobanteFiscal.AsignarEmisor;
begin

  with fXmlComprobante.Emisor do
  begin
    RFC :=(inherited Emisor).RFC;
    Nombre := TFEReglamentacion.ComoCadena((inherited Emisor).Nombre);
    with DomicilioFiscal do // Alias de UbicacionFiscal
    begin
      Calle := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Calle);

      if Trim((inherited Emisor).Direccion.NoExterior) <> '' then
        NoExterior := (inherited Emisor).Direccion.NoExterior; // Opcional

      if Trim((inherited Emisor).Direccion.NoInterior) <> '' then
        NoInterior := (inherited Emisor).Direccion.NoInterior; // Opcional

      if Trim((inherited Emisor).Direccion.Colonia) <> '' then
        Colonia := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Colonia); // Opcional

      if Trim((inherited Emisor).Direccion.Localidad) <> '' then
        Localidad := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Localidad); // Opcional

      if Trim((inherited Emisor).Direccion.Referencia) <> '' then
        Referencia := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Referencia); // Opcional

      Municipio := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Municipio);
      Estado := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Estado);
      Pais := TFEReglamentacion.ComoCadena((inherited Emisor).Direccion.Pais);
      CodigoPostal := (inherited Emisor).Direccion.CodigoPostal;
    end;
  end;
end;

// 2. Lugar y fecha de expedicion (29-A, Fraccion III) - En caso de ser sucursal
procedure TFEComprobanteFiscal.AsignarExpedidoEn;
begin
    // Checamos si tiene direccion de expedicion...
    if (inherited ExpedidoEn.Calle <> '') then
    begin
        with fXmlComprobante.Emisor.ExpedidoEn do
        begin
            Calle := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Calle);
            if Trim((inherited ExpedidoEn).NoExterior) <> '' then
              NoExterior := (inherited ExpedidoEn).NoExterior; // Opcional

            if Trim((inherited ExpedidoEn).NoInterior) <> '' then
              NoInterior := (inherited ExpedidoEn).NoInterior; // Opcional

            if Trim((inherited ExpedidoEn).Colonia) <> '' then
              Colonia := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Colonia); // Opcional
            if Trim((inherited ExpedidoEn).Localidad) <> '' then
              Localidad := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Localidad); // Opcional
            if Trim((inherited ExpedidoEn).Referencia) <> '' then
              Referencia := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Referencia); // Opcional
            Municipio := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Municipio);
            Estado := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Estado);
            Pais := TFEReglamentacion.ComoCadena((inherited ExpedidoEn).Pais);
            CodigoPostal := (inherited ExpedidoEn).CodigoPostal;
        end;
    end;
end;

// 3. Clave del RFC de la persona a favor de quien se expida la factura (29-A, Fraccion IV)
procedure TFEComprobanteFiscal.AsignarReceptor;
begin
  with fXmlComprobante.Receptor do
  begin
    RFC := Trim((inherited Receptor).RFC);
    
    // Si es un CFD de venta al publico en general no incluimos nombre ni direccion
    if (RFC <>_RFC_VENTA_PUBLICO_EN_GENERAL) then
    begin
        Nombre := TFEReglamentacion.ComoCadena((inherited Receptor).Nombre);

        with Domicilio do
        begin
          Calle := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Calle);

          if Trim((inherited Receptor).Direccion.NoExterior) <> '' then
            NoExterior := (inherited Receptor).Direccion.NoExterior; // Opcional

          if Trim((inherited Receptor).Direccion.NoInterior) <> '' then
            NoInterior := (inherited Receptor).Direccion.NoInterior; // Opcional

          if Trim((inherited Receptor).Direccion.Colonia) <> '' then
            Colonia := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Colonia); // Opcional
          if Trim((inherited Receptor).Direccion.Localidad) <> '' then
            Localidad := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Localidad); // Opcional
          if Trim((inherited Receptor).Direccion.Referencia) <> '' then
            Referencia := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Referencia); // Opcional
          Municipio := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Municipio);
          Estado := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Estado);
          Pais := TFEReglamentacion.ComoCadena((inherited Receptor).Direccion.Pais);
          CodigoPostal := (inherited Receptor).Direccion.CodigoPostal;
        end; { with CFD.Receptor.Domicilio }
    end else
        // Si es Publico en General solo agregamos el pais al nodo Direccion
        // cualquier otra cosa generara un CFD invalido.
        Domicilio.Pais:='México';
        
  end; { with CFD.Receptor }
end;

procedure TFEComprobanteFiscal.AsignarContenidoCertificado;
begin
    if Trim(fCertificadoTexto) <> '' then
       fXmlComprobante.Certificado := TFEReglamentacion.ComoCadena(fCertificadoTexto);
end;

procedure TFEComprobanteFiscal.AsignarConceptos;
var
  I: Integer;
  Concepto: TFEConcepto;
begin
     {$IFDEF VER220} CodeSite.EnterMethod('AsignarConceptos'); {$ENDIF}
     // Obtenemos los conceptos agregados al documento previamente
     for I := 0 to Length(inherited Conceptos) - 1 do
     begin
          Concepto:=(inherited Conceptos)[I];

          // Agregamos el concepto al XML
          with fXmlComprobante.Conceptos.Add do
          begin
            Cantidad := TFEReglamentacion.ComoCantidad(Concepto.Cantidad);

            if Trim(Concepto.Unidad) <> '' then
              Unidad := Concepto.Unidad; // Opcional

            if Trim(Concepto.NoIdentificacion) <> '' then
              NoIdentificacion := TFEReglamentacion.ComoCadena(Concepto.NoIdentificacion); // Opcional

            Descripcion := TFEReglamentacion.ComoCadena(Concepto.Descripcion);
            ValorUnitario := TFEReglamentacion.ComoMoneda(Concepto.ValorUnitario);
            Importe := TFEReglamentacion.ComoMoneda(Concepto.ValorUnitario * Concepto.Cantidad);

            // Le fue asignada informacion aduanera??
            if (Concepto.DatosAduana.NumeroDocumento <> '') then
              with InformacionAduanera.Add do
              begin
                Numero := Concepto.DatosAduana.NumeroDocumento;
                Fecha := TFEReglamentacion.ComoFechaAduanera(Concepto.DatosAduana.FechaExpedicion);
                Aduana := TFEReglamentacion.ComoCadena(Concepto.DatosAduana.Aduana);
              end;

            if Trim(Concepto.CuentaPredial) <> '' then
              CuentaPredial.Numero := TFEReglamentacion.ComoCadena(Concepto.CuentaPredial); // Opcional
          end;
     end;
     {$IFDEF VER220} CodeSite.ExitMethod('AsignarConceptos'); {$ENDIF}
end;

procedure TFEComprobanteFiscal.AsignarImpuestosRetenidos;
var
  NuevoImpuesto: TFEImpuestoRetenido;
  I: Integer;
begin
    for I := 0 to Length(inherited ImpuestosRetenidos) - 1 do
    begin
        NuevoImpuesto:=(inherited ImpuestosRetenidos)[I];
        
        with fXmlComprobante.Impuestos.Retenciones.Add do
        begin
          Impuesto := TFEReglamentacion.ComoCadena(NuevoImpuesto.Nombre);
          Importe := TFEReglamentacion.ComoMoneda(NuevoImpuesto.Importe);
        end;
    end;
end;

procedure TFEComprobanteFiscal.AsignarImpuestosTrasladados;
var
  NuevoImpuesto: TFEImpuestoTrasladado;
  I: Integer;
begin
    for I := 0 to Length(inherited ImpuestosTrasladados) - 1 do
    begin
        NuevoImpuesto:=(inherited ImpuestosTrasladados)[I];
        
        with fXmlComprobante.Impuestos.Traslados.Add do
        begin
          Impuesto := TFEReglamentacion.ComoCadena(NuevoImpuesto.Nombre);
          Tasa := TFEReglamentacion.ComoTasaImpuesto(NuevoImpuesto.Tasa);
          Importe := TFEReglamentacion.ComoMoneda(NuevoImpuesto.Importe);
        end;
    end;
end;

procedure TFEComprobanteFiscal.setCertificado(Certificado: TFECertificado);
const
    _CADENA_INICIO_CERTIFICADO = '-----BEGIN CERTIFICATE-----';
    _CADENA_FIN_CERTIFICADO    = '-----END CERTIFICATE-----';
var
  x509Certificado: TX509Certificate;

  // Quita los encabezados, pie y retornos de carro del certificado
  function QuitarCaracteresNoUsadosEnCertificado(sCertificadoBase64: WideString) : WideString;
  begin
      sCertificadoBase64:=StringReplace(sCertificadoBase64, #13, '', [rfReplaceAll, rfIgnoreCase]);
      sCertificadoBase64:=StringReplace(sCertificadoBase64, #10, '', [rfReplaceAll, rfIgnoreCase]);
      // Quitamos encabezado del certificado
      sCertificadoBase64:=StringReplace(sCertificadoBase64, _CADENA_INICIO_CERTIFICADO, '', [rfReplaceAll, rfIgnoreCase]);
      // Quitamos el pie del certificado
      Result:=StringReplace(sCertificadoBase64, _CADENA_FIN_CERTIFICADO, '', [rfReplaceAll, rfIgnoreCase]);
  end;

begin
  // Ya que tenemos los datos del certificado, lo procesamos para obtener los datos
  // necesarios
  x509Certificado := TX509Certificate.Create;
  try
    if Not FileExists(Certificado.Ruta) then
      raise EFECertificadoNoExisteException.Create('No existe el archivo del certificado')
    else
      x509Certificado.LoadFromFile(Certificado.Ruta);

    fCertificado := Certificado;
    
    // Llenamos las propiedades
    fCertificado.VigenciaInicio := x509Certificado.NotBefore;
    fCertificado.VigenciaFin := x509Certificado.NotAfter;

    // Checamos que el certificado este dentro de la vigencia
    if Not((Now >= fCertificado.VigenciaInicio) and (Now <= fCertificado.VigenciaFin)) then
      raise EFECertificadoNoVigente.Create('El certificado no tiene vigencia actual');

    fCertificado.NumeroSerie := x509Certificado.SerialNumber;

    // Ya procesado llenamos su propiedad en el XML
    Assert(Assigned(fXmlComprobante), 'El Nodo comprobante no est asignado!');
    fXmlComprobante.NoCertificado := fCertificado.NumeroSerie;

    // Incluir el certificado en el XML?
    if bIncluirCertificadoEnXML = True then
    begin
       // Obtenemos el certificado codificado en Base64 para incluirlo en el comprobante
       fCertificadoTexto:=X509Certificado.AsBase64;
       fCertificadoTexto:=QuitarCaracteresNoUsadosEnCertificado(X509Certificado.AsBase64);
       //CodeSite.Send('Certificado Base64', CertificadoBase64);
       //CodeSite.Send('length', Length(CertificadoBase64));
    end;

  except
     // Pasamos la excepcion tal y como esta
     On E: Exception do
     begin
        FreeAndNil(x509Certificado);
        raise Exception.Create(E.Message);
     end;
  end;
  FreeAndNil(x509Certificado);
end;

// Asignamos la serie, el no y año de aprobacion al XML...
procedure TFEComprobanteFiscal.AsignarDatosFolios;
begin
   if Trim(fBloqueFolios.Serie) <> '' then
    fXmlComprobante.Serie := fBloqueFolios.Serie;

  fXmlComprobante.NoAprobacion := fBloqueFolios.NumeroAprobacion;
  fXmlComprobante.AnoAprobacion := fBloqueFolios.AnoAprobacion;
end;

// 8. Numero de folio, el cual debe de ser asignado de manera automatica por el sistema
procedure TFEComprobanteFiscal.AsignarFolio;
begin
    fXmlComprobante.Folio := IntToStr(inherited Folio);
end;

// 9. Cumplir con las reglas de control de pagos (Art 29, fraccion V)
procedure TFEComprobanteFiscal.AsignarFormaDePago;
var
  sForma: String;
begin
  case (inherited FormaDePago) of
    fpUnaSolaExhibicion:
      sForma := _CADENA_PAGO_UNA_EXHIBICION;
    fpParcialidades:
      sForma := _CADENA_PAGO_PARCIALIDADES;
  end;
  fXmlComprobante.FormaDePago := sForma;
end;

procedure TFEComprobanteFiscal.AsignarSubtotal;
begin
   fXmlComprobante.SubTotal := TFEReglamentacion.ComoMoneda(inherited Subtotal);
end;

procedure TFEComprobanteFiscal.AsignarTotal;
begin
   fXmlComprobante.Total := TFEReglamentacion.ComoMoneda(inherited Total);
end;

procedure TFEComprobanteFiscal.AsignarMetodoDePago;
begin
  if (Trim(inherited MetodoDePago) <> '') then
     fXmlComprobante.MetodoDePago:=TFEReglamentacion.ComoCadena(inherited MetodoDePago);
end;

procedure TFEComprobanteFiscal.AsignarTipoComprobante;
var
  sTipo: String;
begin
  case (inherited Tipo) of
    tcIngreso:
      sTipo := 'ingreso';
    tcEgreso:
      sTipo := 'egreso';
    tcTraslado:
      sTipo := 'traslado';
  end;

  // TODO: Que cambios deben hacerse cuando es un egreso o traslado???
  fXmlComprobante.TipoDeComprobante := sTipo;
end;

procedure TFEComprobanteFiscal.AsignarTotalesImpuestos;
begin
    // Agregamos al XML los totales de los diferentes tipos de impuestos usados
    // si asi se desea...
    with fXmlComprobante.Impuestos do
    begin
      if (inherited TotalImpuestosRetenidos > 0) then
        TotalImpuestosRetenidos := TFEReglamentacion.ComoMoneda(inherited TotalImpuestosRetenidos); // Opcional

      if (inherited TotalImpuestosTrasladados > 0) then
        TotalImpuestosTrasladados := TFEReglamentacion.ComoMoneda(inherited TotalImpuestosTrasladados); // Opcional
    end;
end;

procedure TFEComprobanteFiscal.AsignarFechaGeneracion;
begin
    // Especificamos la fecha exacta en la que se esta generando el comprobante
    {$IFDEF VERSION_DE_PRUEBA}
      // Si estamos en las pruebas de unidad, dejamos que la prueba
      // defina la fecha/hora en que se "genero" el comprobante
      // para que sea el mismo que se uso al haber sido generado con el MicroE
      if (_USAR_HORA_REAL = True) then
         FechaGeneracion:=Now;
    {$ELSE}
        // Si ya fue generada la factura (por ejemplo cuando se lee)
        FechaGeneracion := Now;
    {$ENDIF}
    // Almacenamos las propiedades del XML antes de generar la cadena original
    fXmlComprobante.Fecha := TFEReglamentacion.ComoFechaHora(FechaGeneracion);
end;

// Funcion encargada de llenar el comprobante fiscal EN EL ORDEN que se especifica en el XSD
// ya que si no es asi, el XML se va llenando en el orden en que se establecen las propiedades de la clase
// haciendo que el comprobante no pase las validaciones del SAT.
procedure TFEComprobanteFiscal.LlenarComprobante;
begin
    if (FacturaGenerada = False) then
    begin
        {$IFDEF VER220} CodeSite.EnterMethod('LlenarComprobante'); {$ENDIF}
        // Atributos de comprobante
        AsignarDatosFolios;
        AsignarFechaGeneracion;
        AsignarFolio;
        AsignarFormaDePago;
        AsignarSubtotal;
        AsignarDescuentos;
        AsignarTotal;
        AsignarTipoComprobante;
        AsignarContenidoCertificado;
        AsignarCondicionesDePago;
        AsignarMetodoDePago;

        // Atributo Emisor
        AsignarEmisor;
        AsignarExpedidoEn;
        // Atributo Receptor
        AsignarReceptor;
        // Atributo conceptos
        //if Trim(fCadenaOriginalCalculada) = '' then
        AsignarConceptos;

        // Atributo Impuestos
        AsignarImpuestosTrasladados;
        AsignarImpuestosRetenidos;

        if (fDesglosarTotalesImpuestos = True) then
           AsignarTotalesImpuestos;

        {$IFDEF VER220} CodeSite.ExitMethod('LlenarComprobante'); {$ENDIF}
    end;
end;


procedure TFEComprobanteFiscal.Cancelar;
begin
  { http://www.validacfd.com/phpbb3/viewtopic.php?f=15&t=113&p=596&hilit=egreso#p596 - User: Carlos R
    Algunos detalles tecnicos-practicos que generalmente se omiten.
    * Al cancelar las facturas se deberá incorporar en los reportes mensuales con "|0|". pero no es tan simple.
    Si es en el mismo dia, tendrás que insertar la serie y el folio primermente en |1| y posteriormente la declaras en |0|,
    no de primera mano en |0|. (ojala me haya explicado)
    Variable1: Cancelas el mismo dia
    Variable2: Cancelas el mes
    Variable3: Cancelas otro mes

    en cualquiera de los casos el sistema tendrá que ser capaz de incorporarlo en el reporte como cancelado.

    Si además de la cancelación se realizó nota de crédito (por devolución o por descuento) el sistema deberá de
    generar el documento como un "egreso", recuerda que para el SAT solo existen: INGRESO, EGRESO, TRASLADO.
  }
end;

procedure TFEComprobanteFiscal.ValidarQueFolioEsteEnRango;
begin
  // Validamos que el folio este dentro del rango definido si ya se nos fue proporcionado
  // el bloque de folios y el numero de folio
  if not FacturaGenerada then
    if ((fBloqueFolios.FolioInicial > -1) And (inherited Folio > -1)) then
    begin
      if Not((inherited Folio >= fBloqueFolios.FolioInicial) And (inherited Folio <= fBloqueFolios.FolioFinal)) then
        raise EFEFolioFueraDeRango.Create('El folio se encuentra fuera del rango autorizado');
    end;
end;

procedure TFEComprobanteFiscal.setBloqueFolios(Bloque: TFEBloqueFolios);
begin
  // Asignamos el bloque a la variable interna y validamos que este dentro del rango...
  fBloqueFolios := Bloque;
  // Establecemos la serie
  inherited Serie := fBloqueFolios.Serie;
  // Si esta asignado el folio
  if Folio > 0 then
    ValidarQueFolioEsteEnRango();
end;

// El metodo que genera el CFD al final...
procedure TFEComprobanteFiscal.GuardarEnArchivo(sArchivoDestino: String);
begin
  fXmlComprobante.Sello:=Self.SelloDigital;
  fDocumentoXML.SaveToFile(sArchivoDestino);
  // TODO: Implementar las diversas fallas que pueden ocurrir
end;

// Calculamos el sello digital para la cadena original de la factura
function TFEComprobanteFiscal.getSelloDigital(): String;
var
  TipoDigestion: TTipoDigestionOpenSSL;
  SelloDigital: TSelloDigital;
begin
  // Si la factura ya fue generada regresamos el sello previamente calculado
  if (FacturaGenerada = True) then
  begin
      Result:=fSelloDigitalCalculado;
  end else
  begin
      // Si aun no ha sido generada la factura la "llenamos"
      LlenarComprobante;
      fSelloDigitalCalculado:='';
      // Segun la leglislacion vigente si la factura se hace antes del 1 de Enero del 2011, usamos MD5
      if Now < EncodeDate(2011, 1, 1) then
        TipoDigestion := tdMD5
      else // Si es 2011 usamos el algoritmo SHA-1
        TipoDigestion := tdSHA1;
      try
        // Creamos la clase SelloDigital que nos ayudara a "sellar" la factura en XML
        SelloDigital := TSelloDigital.Create(Self.CadenaOriginal, fCertificado, TipoDigestion);

        // Finalmente regresamos la factura en XML con todas sus propiedades llenas
        fSelloDigitalCalculado := SelloDigital.SelloCalculado;
      except
        // TODO: Manejar los diferentes tipos de excepciones...
        on E:Exception do
           raise E.Create(E.Message);
      end;
      // Liberamos la clase de sello usada previamente
      FreeAndNil(SelloDigital);
      FacturaGenerada:=True;
      result := fSelloDigitalCalculado;
  end;
end;

// Permite establecer el XML del comprobante (por si se esta leyendo de la BD, etc)
// y almacena todo en la estructura interna de datos y XML
procedure TFEComprobanteFiscal.setXML(Valor: WideString);
var
  I: Integer;
  ValorEmisor, ValorReceptor: TFEContribuyente;
  feConcepto: TFEConcepto;
  iXmlDoc: IXMLDocument;
  ValorExpedidoEn: TFEExpedidoEn;
  ImpuestoTrasladado: TFEImpuestoTrasladado;
  ImpuestoRetenido: TFEImpuestoRetenido;
begin
    try
        // Leemos el contenido XML en el Documento XML interno
        iXmlDoc:=LoadXMLData(UTF8Decode(Valor));
        // Creamos el documento "dueño" del comprobante
        fDocumentoXML:=TXmlDocument.Create(nil);
        // Pasamos el XML para poder usarlo en la clase
        fDocumentoXML.XML:=iXmlDoc.XML;
        // Asignamos el XML a la variable interna del componnente
        fXmlComprobante := GetComprobante(fDocumentoXML);
        
        // Ahora, actualizamos todas las variables internas (de la clase) con los valores del XML
        with fXmlComprobante do
        begin
            inherited Folio:=StrToInt(Folio);
            // Datos del certificado
            fCertificado.NumeroSerie:=NoCertificado;
            fCertificadoTexto := Certificado;
            fBloqueFolios.NumeroAprobacion:=NoAprobacion;
            fBloqueFolios.AnoAprobacion:=AnoAprobacion;
            fBloqueFolios.Serie:=Serie;
            inherited Serie:=Serie;
            fBloqueFolios.FolioInicial:=inherited Folio;
            fBloqueFolios.FolioFinal:=inherited Folio;

            FechaGeneracion:=TFEReglamentacion.ComoDateTime(fXmlComprobante.Fecha);

            inherited CondicionesDePago:=CondicionesDePago;
            inherited MetodoDePago:=MetodoDePago;

            // Leemos los datos del emisor
            ValorEmisor.Nombre:=Emisor.Nombre;
            ValorEmisor.RFC:=Emisor.RFC;
            with Emisor do
            begin
                ValorEmisor.Direccion.Calle := DomicilioFiscal.Calle;
                ValorEmisor.Direccion.NoExterior := DomicilioFiscal.NoExterior;
                ValorEmisor.Direccion.NoInterior := DomicilioFiscal.NoInterior;
                ValorEmisor.Direccion.CodigoPostal := DomicilioFiscal.CodigoPostal;
                ValorEmisor.Direccion.Colonia := DomicilioFiscal.Colonia;
                ValorEmisor.Direccion.Localidad := DomicilioFiscal.Localidad;
                ValorEmisor.Direccion.Municipio := DomicilioFiscal.Municipio;
                ValorEmisor.Direccion.Estado := DomicilioFiscal.Estado;
                ValorEmisor.Direccion.Pais := DomicilioFiscal.Pais;
            end;
            inherited Emisor:=ValorEmisor;

            // Leemos los datos del receptor
            ValorReceptor.Nombre:=Receptor.Nombre;
            ValorReceptor.RFC:=Receptor.Rfc;
            with Receptor do
            begin
                ValorReceptor.Direccion.Calle := Domicilio.Calle;
                ValorReceptor.Direccion.NoExterior := Domicilio.NoExterior;
                ValorReceptor.Direccion.NoInterior := Domicilio.NoInterior;
                ValorReceptor.Direccion.CodigoPostal := Domicilio.CodigoPostal;
                ValorReceptor.Direccion.Colonia := Domicilio.Colonia;
                ValorReceptor.Direccion.Localidad := Domicilio.Localidad;
                ValorReceptor.Direccion.Municipio := Domicilio.Municipio;
                ValorReceptor.Direccion.Estado := Domicilio.Estado;
                ValorReceptor.Direccion.Pais := Domicilio.Pais;
            end;
            inherited Receptor:=ValorReceptor;

            // Tiene emisor??
            if (Emisor.ExpedidoEn.Calle <> '') then
            begin
                with Emisor.ExpedidoEn do
                begin
                    ValorExpedidoEn.Calle := Calle;
                    ValorExpedidoEn.NoExterior := NoExterior;
                    ValorExpedidoEn.CodigoPostal := CodigoPostal;
                    ValorExpedidoEn.Localidad := Localidad;
                    ValorExpedidoEn.Municipio := Municipio;
                    ValorExpedidoEn.Colonia := Colonia;
                    ValorExpedidoEn.Estado := Estado;
                    ValorExpedidoEn.Pais := Pais;
                end;
            end;
            inherited ExpedidoEn:=ValorExpedidoEn;

            for I := 0 to Conceptos.Count - 1 do
            begin
                feConcepto.Cantidad:=StrToFloat(Conceptos[I].Cantidad);
                feConcepto.Unidad:=Conceptos[I].Unidad;
                feConcepto.Descripcion:=Conceptos[I].Descripcion;
                feConcepto.ValorUnitario:=StrToFloat(Conceptos[I].ValorUnitario);
                feConcepto.NoIdentificacion:=Conceptos[I].NoIdentificacion;

                inherited AgregarConcepto(feConcepto);
            end;

            // Agregamos las reteneciones
            for I := 0 to Impuestos.Retenciones.Count - 1 do
            begin
              with Impuestos.Retenciones do
              begin
                ImpuestoRetenido.Nombre := Retencion[I].Impuesto;
                ImpuestoRetenido.Importe := StrToFloat(Retencion[I].Importe);

                inherited AgregarImpuestoRetenido(ImpuestoRetenido);
              end;
            end;

            // Agregamos los traslados
            for I := 0 to Impuestos.Traslados.Count - 1 do
            begin
              with Impuestos.Traslados do
              begin
                ImpuestoTrasladado.Nombre := Traslado[I].Impuesto;
                ImpuestoTrasladado.Tasa:= StrToFloat(Traslado[I].Tasa);
                ImpuestoTrasladado.Importe := StrToFloat(Traslado[I].Importe);

                inherited AgregarImpuestoTrasladado(ImpuestoTrasladado);
              end;
            end;

            if (Impuestos.TotalImpuestosTrasladados <> '') then
                Self.DesglosarTotalesImpuestos := True
            else
                Self.DesglosarTotalesImpuestos := False;

            // Que forma de pago tuvo??
            if AnsiPos('UNA', Uppercase(FormaDePago)) > 0 then
                inherited FormaDePago := fpUnaSolaExhibicion
            else
                inherited FormaDePago := fpParcialidades;

            // Tipo de comprobante
            if TipoDeComprobante = 'ingreso' then
              inherited Tipo := tcIngreso;

            if TipoDeComprobante = 'egreso' then
              inherited Tipo := tcEgreso;

            if TipoDeComprobante = 'traslado' then
              inherited Tipo := tcTraslado;

            // Asignamos el descuento
            if (Descuento <> '') then
              Self.AsignarDescuento(StrToFloat(Descuento), MotivoDescuento);

            // Asignamos el subtotal de la factura
            inherited SubTotal := StrToFloat(Subtotal);

            // Asignamos el sello que trae el XML
            fSelloDigitalCalculado:=Sello;

            // Ahora hacemos que se calcule la cadena original de nuevo
            fCadenaOriginalCalculada:=getCadenaOriginal;
            
            // Finalmente indicamos que la factura ya fue generada
            FacturaGenerada:=True;

            Assert(Self.Total = StrToCurr(Total), 'El total del comprobante no fue igual que el total del XML');
        end;
    except
        On E:Exception do
          Raise E;
    end;
end;

// Regresa el XML final del comprobante ya lleno
function TFEComprobanteFiscal.getXML(): WideString;
begin
    // Checamos si ya fue generada previamente la factura
    if FacturaGenerada = True then
        Result:=fDocumentoXML.XML.Text
    else
        Raise Exception.Create('No se puede obtener el XML cuando aún no se ha generado el archivo CFD');
end;

end.
