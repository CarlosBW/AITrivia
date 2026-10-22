# Checklist de lanzamiento — TriviaIA

Este documento cubre lo que **queda pendiente y no se puede resolver con código** — son acciones manuales en consolas/cuentas que solo tú puedes hacer. Todo lo demás (código, tests, CI, políticas legales, App Check, Crashlytics, eliminación de cuenta) ya está resuelto en este repo.

**Estado actual (2026-10-14):** el `applicationId`/bundle ID real (`pe.massivedynamics.triviaia`) ya está adoptado en Android e iOS desde el 2026-10-08, y la tienda ya vende temas visuales por monedas (punto 6). Lo que falta se reduce a cinco cosas:

1. Los puntos **2 (parte final)** y **4**: completar App Check, que espera la clave de firma de Play y el Team ID de Apple, y lo demás que depende de Play Console y App Store Connect.
2. La **revisión legal** del punto 5 — de contenido, no de código. (La revisión factual del banco, punto 7, quedó hecha el 2026-10-10.)
3. La **compra de monedas** con dinero real (punto 6): sigue en "Próximamente" hasta que existan los productos en las tiendas.
4. La configuración y las pruebas del inicio de sesión con Google o Apple (punto **8**).
5. **Web** (punto 2, último ítem) solo si vas a lanzar esa plataforma.

### Para retomar (anotado el 2026-10-14, para seguir desde la PC de escritorio)

Lo que se puede hacer sin esperar a Google ni a Apple, en este orden:

1. ~~**Ponerse al día.**~~ — hecho el 2026-10-15: `git pull`, y el CLI de Firebase ya usa `apps@` (ver punto 1b).
2. ~~**Política de claves de cuentas de servicio**~~ — hecho el 2026-10-15: activa y heredada por el proyecto; ver el último ítem del punto 1b.
3. **Cuentas de prueba** de producción (punto 6, "Limpieza antes de lanzar"): `ClaudeShopTest` y `ClaudeShopTest2`, borradas el 2026-10-15. El anónimo `C84wqr2v0JWZvQ7PvK1gf6uxsLD3` queda **pospuesto** hasta terminar de agregar temas nuevos, porque sirve para probarlos; se borra justo antes de lanzar, junto con las cuentas que creen las pruebas que vengan.
4. **Keystore de release** (punto 4), en la PC que vaya a compilar las versiones para la tienda. Los pasos:
   - Crear el `.jks` con `keytool -genkeypair … -alias upload`, fuera del repo.
   - Crear `android/key.properties` con `storePassword`, `keyPassword`, `keyAlias=upload` y la ruta absoluta del `.jks` en `storeFile`.
   - Comprobar con `flutter build appbundle --release` que ya no sale el aviso de "key.properties no existe".
   - Agregar sus huellas SHA-1 y SHA-256 a la app Android en Firebase y volver a descargar `google-services.json`.
   - Guardar copia del `.jks` y su contraseña fuera de la PC.
5. **Pruebas en el emulador** `Medium_Phone_API_36.1` de esa PC, que ya tiene registrado su token de depuración de App Check:
   - Guardar el progreso con Google (punto 8): vincular desde Perfil, reinstalar y recuperar con "Ya tengo una cuenta".
   - Recorrer los temas (punto 6), sobre todo lo que nunca se vio en pantalla: notificaciones y amigos con contenido, Weekly Topic, resultado del Daily Challenge, y los colores del marco y de las ligas.
6. **Revisión legal** (punto 5): llevar `public/privacy.html` y `public/terms.html` a un abogado.

En espera de Google y Apple: crear las apps en las consolas, los productos de monedas y el permiso de la cuenta de servicio en Play Console (punto 6), la huella de firma de Play, el Team ID para App Attest, todo lo de iOS, los formularios de Data Safety y el *Enforce* de App Check. La verificación de recibos de Google Play ya está escrita; falta desplegarla cuando existan los productos.

## 1. Deploy pendiente

- [x] `firebase deploy --only hosting` — hecho, `public/privacy.html` y `public/terms.html` están en vivo con el nombre legal correcto (Massive Dynamics Peru S.A.C.).
- [x] `npm run deploy` en `functions/` — hecho, `deleteMyAccount` y el manejo de `refusal` ya están en producción.
- [x] `firebase deploy --only firestore:indexes` (2026-08-07) — los 16 índices ya estaban en vivo, pero los dos `fieldOverrides` de collection-group (`sent_friend_requests.targetUid`, `friend_requests.requesterUid`) nunca se habían desplegado: `--only firestore:rules` no toca índices, y son deploys separados. Sin ellos, la limpieza de espejos de solicitudes de amistad en `deleteMyAccount` fallaba en silencio. Verificado que ambos terminaron de construirse ejecutando las queries reales contra producción.
- [x] Funciones desplegadas el 2026-10-13, una por una con `firebase deploy --only functions:<nombre>` en vez de las ~40: `purchaseTheme` (precios de los temas nuevos) y `submitSoloLevelResult` (ver punto 9). No queda ningún cambio de `functions/` sin desplegar.
- [x] `firebase deploy --only hosting` (2026-10-14): la política de privacidad y los términos en vivo ya describen el inicio de sesión opcional con Google o Apple (ver "Publicación" en el punto 8). No queda ningún otro deploy pendiente.
- [x] `purchaseTheme` desplegada con el precio del tema Espacio (2026-10-15). Comprobado contra producción con la cuenta de prueba sin monedas: pedir `space` responde "No tienes suficientes monedas" (el servidor conoce el tema), y un id inventado sigue respondiendo `invalid-argument`. No se cobró nada. Las 40 callables siguen invocables.
- [x] `purchaseTheme` desplegada con el precio del tema Vintage (2026-10-15), tras renovar la sesión del CLI con `firebase login --reauth`. Sin comprobar contra producción: pedir `vintage` con la cuenta del emulador debería responder "No tienes suficientes monedas", como pasó con `space`.
- [x] `purchaseTheme` desplegada con el precio del tema Apocalipsis (2026-10-15). Sin comprobar contra producción: pedir `apocalypse` con la cuenta del emulador debería responder "No tienes suficientes monedas", como pasó con `space`.
- [x] `purchaseTheme` desplegada con el precio del tema Cyberpunk (2026-10-15). Sin comprobar contra producción, igual que Apocalipsis.
- [x] `purchaseTheme` desplegada con los precios de Steampunk y Navidad (2026-10-15). Sin comprobar contra producción, igual que Apocalipsis.
- [ ] `npm run deploy` en `functions/` (bloque 4, 2026-10-21). Toca muchas funciones a la vez, así que va el deploy completo y no una por una: `localizedError` marca ahora sus mensajes como traducidos (la app solo muestra esos y, para el resto, su propio texto), varios errores que el jugador sí puede provocar pasaron a español/inglés (código de sala, retos pendientes, tema de la semana terminado, límite de temas IA, título largo, jugador que ya no existe), y `rotateWeeklyTopic` escribe `title_es`/`title_en`. Después, rellenar esos dos campos en `weekly_topics/current` para no esperar al lunes: hoy dice "Science Week" también en español.
- [ ] `firebase deploy --only functions:reportQuestion,functions:reportAiQuestion` (bloque 5, 2026-10-22): el botón "Revisar preguntas" al final de Solo, Reto diario y Tema de la semana. Mientras no esté desplegada, reportar responde "No pudimos enviar el reporte.". Después, revisar los reportes de vez en cuando con `node tools/export_question_reports.js` → `apply_question_fixes.js` → `export_question_reports.js --cerrar --commit`; nada se corrige ni se esconde solo.

## 1b. El proyecto en la organización de la empresa

El 2026-10-11 `trivia-ia-app` pasó de no tener organización a colgar de `massivedynamics.pe` (ID `358422649310`), creada con Cloud Identity Free. El ID del proyecto, los datos y las funciones no cambiaron, y no hubo corte.

- [x] Proyecto movido, con `apps@massivedynamics.pe` como administrador de la organización.
- [x] **Excepción a *Domain restricted sharing* en el proyecto.** La organización nueva trae activa la política que solo permite dar permisos a cuentas `@massivedynamics.pe`. Cada callable necesita `allUsers -> roles/run.invoker` para que la app la llame, así que sin la excepción un deploy no puede volver a aplicar ese permiso. Está en IAM → Organization Policies del proyecto: *Override parent's policy*, *Replace*, *Allow All*. Si algún deploy falla con "do not belong to a permitted customer" o "Unable to set the invoker", lo primero es mirar que esa excepción siga ahí.
- [x] Verificado tras el traslado: 40 de 40 callables invocables, y un deploy de `refreshUserLives` desde dentro de la organización terminó bien.
- [x] `apps@massivedynamics.pe` tiene el rol **Owner** sobre el proyecto: la invitación pendiente quedó aceptada (verificado el 2026-10-14).
- [x] Cuenta de facturación `Massive Dynamics Peru S.A.C.` (`01E279-5EDCFD-649EF4`) movida de `cbalcazarwong-org` (ID `935552953470`) a `massivedynamics.pe` (2026-10-14), con *Change organization* desde la página de la cuenta. El proyecto siguió cobrándose a ella todo el tiempo. Cómo se logró, por si hay que repetir algo parecido:
  - El botón aparece desactivado ("You don't have permission…") si la cuenta que mueve no puede ver la organización de **origen**; la pista es que la cuenta muestre "Unknown organization".
  - El Gmail no puede hacerlo: sería administrador del origen, pero la restricción de dominio de `massivedynamics.pe` impide darle permisos en el destino.
  - Se hizo con `apps@`, con permisos en los dos lados: *Billing Account Administrator* sobre la cuenta de facturación, más *Billing Account Administrator* y *Organization Viewer* sobre `cbalcazarwong-org`, otorgados desde el Gmail.
  - Los roles de IAM tardaron en aplicarse: hizo falta cerrar sesión y volver a entrar con `apps@` antes de que viera la organización.
- [x] Quitados a `apps@` los dos roles que se le dieron en `cbalcazarwong-org` solo para la mudanza (2026-10-14). El de *Billing Account Administrator* **sobre la cuenta de facturación** se quedó: es el que le permite administrarla.
- [x] El presupuesto de S/25 siguió con la cuenta al cambiar de organización (verificado el 2026-10-14 en Facturación → Presupuestos y alertas).
- [x] `cbalcazarwong@gmail.com` quitada del proyecto y de la cuenta de facturación (2026-10-14), después de pasar el CLI de Firebase a `apps@massivedynamics.pe` y de comprobar que un deploy de hosting funcionaba con esa cuenta. `cbalcazarwong-org` se quedó como estaba: ya no contiene nada del proyecto.
- [x] El CLI de Firebase usa `apps@` en las dos máquinas: la laptop, y la PC de escritorio desde el 2026-10-15, cuando dejó el Gmail con `firebase logout` y `firebase login`. Comprobado con `firebase login:list`, y `firebase projects:list` ve `trivia-ia-app`.
- [x] **Política de claves de cuentas de servicio** (revisada el 2026-10-15). `iam.managed.disableServiceAccountKeyCreation` está **activa** en la organización, y `trivia-ia-app` la hereda sin excepción; la versión legacy, `iam.disableServiceAccountKeyCreation`, está inactiva, pero basta con una. Se deja así a propósito. La clave de `tools/serviceAccountKey.json` sigue valiendo, porque la política solo impide crear claves nuevas. Si algún día hay que reemplazarla, por ejemplo porque se filtró, primero hay que crear en el proyecto una excepción a esa política, igual que la de *Domain restricted sharing*, y quitarla después.

## 2. Firebase App Check (protección contra bots/clientes modificados)

El cliente Flutter ya activa App Check (`main.dart`), pero **no hace nada hasta que lo registres**. El registro dependía del `applicationId`/bundle ID final, que ya está definido (`pe.massivedynamics.triviaia`, 2026-10-08):

- [x] Habilitar la **Play Integrity API** en Google Cloud Console (proyecto `trivia-ia-app`) — a nivel de proyecto, no depende del package name, ya se puede hacer.
- [x] Habilitar la **Firebase App Check API** (2026-08-07). Es **distinta** de la Play Integrity API: aquella es el proveedor que atestigua el dispositivo, esta es el servicio que emite y valida los tokens. Estuvo deshabilitada mientras la otra ya estaba lista, así que App Check emitía un token placeholder en silencio en vez de fallar de forma visible. Se detectó por el `403 ... App Check API has not been used in project` en el log de la app.
- [x] Registrar la app Android `pe.massivedynamics.triviaia` con **Play Integrity** (2026-10-14), con la huella SHA-256 de la clave debug de la PC de escritorio (`C1:13:7D:…:10:BA`) y tokens de 1 hora. Solo las apps `pe.massivedynamics.triviaia`; las de `com.example.*`, web y Windows quedan sin registrar a propósito.
- [x] **Token de depuración** del emulador `Medium_Phone_API_36.1` de la PC de escritorio registrado (2026-10-14, Firebase Console → App Check → app Android → ⋮ → Administrar tokens de depuración). Verificado: la app guardó un token de App Check real y llegó a leer Firestore sin errores. El token es por instalación: desinstalar la app o borrar sus datos genera otro, y la laptop o un teléfono físico necesitan el suyo. Lo imprime el log al arrancar en debug ("Enter this debug secret into the allow list…"). No va al repo.
- [ ] Agregar en la app Android de Firebase la huella SHA-256 de la **clave de firma de Play** (Play Console → Integridad de la app), y la de la clave de subida. La de debug registrada no sirve para los usuarios reales, que instalan desde la tienda: Play Integrity sí depende del punto 4.
- [ ] Registrar la app iOS `pe.massivedynamics.triviaia` con **App Attest**. Pide el Team ID, que solo existe con la membresía de Apple Developer.
- [ ] Una vez registrado y verificado que la app real está mandando tokens válidos, **recién ahí** activa "Enforce" en Firestore y en Cloud Functions. Si activas "Enforce" antes de registrar la app, bloqueas a todos los usuarios reales.
- [ ] Web no está cubierto todavía (necesita una site key de reCAPTCHA) — si vas a lanzar la versión web, avísame y lo agrego.

## 3. Control de gasto en IA (dinero real desde el 2026-08-04)

Hasta que la API key de Anthropic quedó válida (2026-08-04), el gasto era estructuralmente cero. Ya no. Como el login es anónimo e ilimitado y cada cuenta nueva trae un pase gratis, existe un camino de "cualquiera con el app" a gasto real.

- [x] **Tope diario en el servidor** (`functions/src/ai_budget.ts`): 5000 niveles/día a nivel proyecto (≈500 temas completos, ≈$15 USD/día en el peor caso con el costo medido abajo) y 50/día por cuenta. Sugerencias de títulos tienen su propio medidor (2000/día global, 30/día por cuenta). Contadores en `ai_usage/{fecha}`, con fecha del servidor y transacción, así que ni el reloj del cliente ni dos llamadas simultáneas los saltan. Para cambiar los topes: `AI_METER_CAPS` en ese archivo, y redesplegar.
- [x] **Alerta de presupuesto en Google Cloud** (2026-08-07, recreada el 2026-10-11): presupuesto mensual de S/25 sobre el proyecto `trivia-ia-app`, con alertas al 50/90/100%. Los presupuestos pertenecen a la cuenta de facturación, no al proyecto: la original estaba en la cuenta de prueba, que venció el 2026-09-09 y dejó el proyecto sin facturación — y la app caída — hasta el 2026-10-10. La actual está en la cuenta `Massive Dynamics Peru S.A.C.` (`01E279-5EDCFD-649EF4`) y avisa a sus administradores; desde el 2026-10-14 es solo `apps@massivedynamics.pe`, porque el Gmail salió de la cuenta (punto 1b). Si algún día se cambia de cuenta de facturación, hay que volver a crearla. Dos límites que conviene tener presentes: **solo notifica, no corta** (la columna "Spend cap status" dice "Not applicable" — los presupuestos de Cloud Billing nunca detienen el gasto), y **no ve el gasto de Anthropic**, porque las funciones llaman a la API de primera parte (`new Anthropic({apiKey})`), que Anthropic factura aparte. Cubre Firestore, Functions y hosting, que es el gasto barato.
- [x] **Techo duro del gasto en IA**: la cuenta de Anthropic funciona con créditos prepagados y la **recarga automática está desactivada** (verificado 2026-08-07), así que el saldo cargado es el tope real y no se puede gastar de más. Con ~$25 de saldo y un peor caso de ~$15/día, eso es algo más de un día de abuso máximo antes de que la API deje de responder.
- [x] **Límite de gasto en Anthropic Console** (2026-10-10): USD 100 al mes, en Facturación → Límites de gasto. El valor por defecto era USD 200 000, que no protegía de nada. Es el segundo freno, detrás del saldo prepagado: si algún día se activa la recarga automática, pasa a ser el único.
- Nota sobre el fallo por saldo agotado: `createAiTopic` **cobra después de generar** (`index.ts`: genera en ~6424, cobra en la transacción de ~6458), así que si Claude falla por falta de créditos el jugador no pierde monedas ni su pase gratis. La degradación es limpia: deja de poder crear temas IA, y el resto del juego (solo, PvP, diario, semanal) no toca Anthropic.
- Referencia de costo, **medida** el 2026-10-10 con Haiku 5.5: USD 0.04 por 14 generaciones de 10 preguntas, o sea ~$0.003 por nivel y ~$0.03 por tema completo de 10 niveles. Es el extremo bajo de lo que costaba Haiku 4.5 (~$0.03–0.05) y no la décima parte que sugiere el precio por token: Haiku 5.5 razona antes de responder y esos tokens se pagan como salida. Apagar el razonamiento (`thinking: {type: "disabled"}`) lo bajaría a cerca de $0.01 por tema, a cambio de calidad no medida.
- Nota: el enforcement de App Check (punto 2) es la solución de fondo a este riesgo — los topes son un paliativo mientras siga bloqueado por las cuentas de las tiendas.

## 4. Cuentas de las tiendas (fuera de alcance por ahora, como acordamos)

- [x] Definir el `applicationId`/bundle ID real (2026-10-08): `pe.massivedynamics.triviaia` en Android (`android/app/build.gradle.kts`) y en iOS (`ios/Runner.xcodeproj`). macOS sigue con el placeholder `com.example.triviaIaFlutter`; no es una plataforma de lanzamiento.
- [ ] Play Console: crear la app con ese `applicationId` y generar el keystore de release.
  - El lado de código ya está listo: `android/app/build.gradle.kts` lee `android/key.properties` (claves `keyAlias`, `keyPassword`, `storeFile`, `storePassword`) y firma release con esa clave. Solo falta crear el keystore y ese archivo — **no lo commitees**, ya está en `.gitignore`. Mientras `key.properties` no exista, el build release cae a la debug key y Gradle lo avisa con un `WARNING`; ese AAB no es publicable en Play.
- [ ] App Store Connect: crear la app con ese bundle ID.
- [x] Regenerar `google-services.json` / `GoogleService-Info.plist` con `flutterfire configure` (2026-10-08). Creó una segunda app Android y una segunda app iOS en el proyecto `trivia-ia-app`, así que los appIds cambiaron junto con el identificador.
- [ ] Agregar `ios/Runner/GoogleService-Info.plist` al target Runner en Xcode. El archivo está en el repo pero nada lo referencia: `flutterfire` no puede editar `project.pbxproj` desde Windows.
- [ ] Notificaciones push en iOS. El código ya está (2026-10-21): `ios/Runner/Runner.entitlements` con `aps-environment`, enlazado en `project.pbxproj`, y el `AppDelegate` como delegado de notificaciones. Falta, en consolas: activar la capacidad **Push Notifications** en el App ID `pe.massivedynamics.triviaia` (Apple Developer → Identifiers) y subir una **APNs Authentication Key** (.p8) en Firebase Console → Configuración del proyecto → Cloud Messaging → app iOS. Sin la clave, FCM no puede entregar nada a iPhone.
- [ ] Registrar App Check en Firebase Console (ver punto 2) — usa el mismo `applicationId`/bundle ID.
- [ ] Formulario de "Data Safety" (Google Play) y "Privacy Nutrition Label" (Apple) — usa el contenido de `public/privacy.html` como base.

## 5. Revisión legal — guía entregada

- [x] `public/privacy.html` y `public/terms.html` son un borrador funcional basado en lo que la app realmente recolecta (cuenta anónima, progreso de juego, amigos, notificaciones push, títulos de temas de IA enviados a Anthropic), ya con el nombre legal correcto (Massive Dynamics Peru S.A.C.). **No reemplaza asesoría legal.** Puntos específicos a llevarle a un abogado: la sección de ley aplicable (hoy asume Perú), necesidad de lenguaje GDPR si vas a tener usuarios en la UE, la cláusula de privacidad de menores, y (más adelante) la de reembolsos cuando actives compras dentro de la app. Si tu empresa ya tiene abogado/notario de la constitución, es el candidato natural para esta revisión.

## 6. Monetización (Tienda)

La tienda tiene dos mitades que dependen de cosas distintas: los temas se compran con monedas que el jugador ya tiene, y las monedas se comprarían con dinero real.

**Temas visuales — funcionando (2026-10-13)**

- [x] Doce temas en la tienda: Clásico (gratis), Océano, Atardecer y Bosque (250 monedas cada uno, solo cambian la paleta), Juguetón, Noche, Espacio, Vintage, Apocalipsis, Cyberpunk, Steampunk y Navidad (400; cambian contornos y sombras, pasan a fondo oscuro, dibujan un fondo propio o cambian la letra de los titulares). El catálogo vive en `lib/theme/app_themes.dart` y el precio que de verdad se cobra en `THEME_PRICES` de `functions/src/index.ts`; un test impide que se desalineen.
- [x] Compra probada de punta a punta contra producción con una cuenta de prueba: Noche, Océano, Atardecer y Bosque. El saldo baja, el tema se equipa al momento y cambiar entre temas ya comprados no vuelve a cobrar. Juguetón no se llegó a comprar.
- [ ] **Verlos en un teléfono real.** Toda la revisión visual fue en web a tamaño de teléfono. Noche se recorrió casi entera y Atardecer a fondo; Océano y Bosque solo en Inicio, Tienda, PvP y una partida. Sin ver en ningún tema: listas de amigos y notificaciones con contenido, Weekly Topic y el resultado del Daily Challenge. Tampoco se vieron los colores corregidos de la etiqueta del marco y de los nombres de liga (punto 9): quedaron respaldados solo por tests.
- Los temas solo aparecen en builds nuevos: quien tenga una versión anterior sigue viendo Clásico y Juguetón hasta actualizar.
- [x] **Espacio** (2026-10-15): el primer tema que dibuja además de colorear. Trae un cielo de estrellas fijas con una nebulosa detrás de cada pantalla, íconos espaciales en la barra (planeta, cohete, constelación, cristal) y tarjetas con un borde fino luminoso y un resplandor en lugar de sombra. El fondo lo pone el tema al abrir cada pantalla (`lib/theme/starfield_backdrop.dart`), así que ninguna pantalla sabe que existe; los íconos están en `lib/widgets/nav_glyphs.dart`. Visto en el emulador con `PREVIEW_THEME=space`: registro de usuario, bienvenida, Inicio, Tienda y PvP. Sin ver: una compra real con monedas (el precio ya está en el servidor, punto 1), partidas, perfil, amigos y el resto de pantallas. Las tarjetas con lavado semitransparente dejan ver las estrellas a través, como en Noche dejan ver la página.
- [x] **Vintage** (2026-10-15): papel envejecido detrás de cada pantalla (tono irregular, grano, fibras, manchas de antigüedad y el borde inferior algo más oscuro), tinta sepia sobre crema con granate como color de marca, tarjetas con filete fino de tinta y sombra dura desplazada, y esquinas más rectas. Es el primer tema que cambia la letra: titulares, puntajes y barras en Playfair Display (`AppHeadingFace.serif`); el texto corrido sigue en Manrope. El papel está en `lib/theme/paper_backdrop.dart` y entra por el mismo camino que el cielo de Espacio. La barra trae su propio juego de íconos (`AppNavIcons.vintage`): casa con chimenea, floretes cruzados, dos caballeros con chistera y bombín, y un letrero de tienda colgado con una moneda; revisados renderizados a 120 y a 24 px, sin ver aún en la app. Visto en web con `PREVIEW_THEME=vintage`: selección de idioma y nombre de usuario. Sin ver: todo lo que exige cuenta (Inicio, Tienda, partidas, PvP, perfil) y una compra real.
- [x] **Apocalipsis** (2026-10-15, id `apocalypse`): tema oscuro de concreto agrietado con manchas de hollín y óxido, polvo y una neblina anaranjada abajo (`lib/theme/wasteland_backdrop.dart`), óxido como color de marca, amarillo de peligro para las recompensas y verde radiactivo para los aciertos. Tarjetas como placas de metal: borde, sombra dura hacia abajo y esquinas casi rectas. Titulares en letra de esténcil militar, Black Ops One (`AppHeadingFace.stencil`); esa letra trae un solo peso, así que nunca se le pide negrita. Íconos propios (`AppNavIcons.apocalypse`): búnker con escotilla y tubo de ventilación, llave inglesa y palanca cruzadas, dos sobrevivientes con gafas, y una caja de suministros; revisados renderizados a 120 y a 24 px, junto con el fondo a tamaño de teléfono. Su precio ya está desplegado en `purchaseTheme` (punto 1).
- [x] **Cyberpunk** (2026-10-15, id `cyberpunk`): tema oscuro con una ciudad de noche detrás de cada pantalla (`lib/theme/neon_city_backdrop.dart`): resplandores magenta y cian, una fila de torres oscuras abajo con ventanas encendidas y bordes de neón en algunas azoteas, y líneas de barrido muy tenues. Magenta como color de marca, cian para los bordes y amarillo eléctrico para las recompensas. Tarjetas con borde cian y una sombra magenta dura corrida hacia un lado, como un fallo de señal; esquinas casi rectas. Titulares en Chakra Petch (`AppHeadingFace.tech`), que llega solo hasta el peso 700: nunca se le pide más. Íconos propios (`AppNavIcons.cyberpunk`): torre con antena y ventanas, rayo, dos personas con visor, y un microchip; revisados renderizados a 120 y a 24 px, junto con el fondo a tamaño de teléfono.
- [x] **Steampunk** (2026-10-15, id `steampunk`): tema oscuro de taller victoriano, con engranajes de latón muy tenues detrás de cada pantalla (algunos se salen por los lados y por abajo), un tubo de cobre y la luz cálida de una lámpara (`lib/theme/gears_backdrop.dart`). Latón como color de marca, cobre y verdín. Tarjetas como placas con el borde de latón más grueso de todos los temas (2 px). Titulares en Cinzel, letra grabada (`AppHeadingFace.engraved`). Íconos propios (`AppNavIcons.steampunk`): casa con un engranaje y chimenea humeante, dos engranajes engranados, dos personas con sombrero de copa y gafas de aviador, y una caja registradora antigua con manivela.
- [x] **Navidad** (2026-10-15, id `christmas`): noche de pinos con nieve cayendo detrás de cada pantalla, unos pocos copos en forma de estrella, montículos de nieve abajo y un resplandor dorado (`lib/theme/snowfall_backdrop.dart`). Rojo vivo como color de marca, con texto oscuro en los botones (un rojo que se lea como texto sobre el verde oscuro no aguanta texto blanco encima), dorado y verde. Tarjetas más redondas que las clásicas, con un hilo dorado. Titulares en Mountains of Christmas (`AppHeadingFace.festive`), que llega hasta 700: nunca se le pide más. Íconos propios (`AppNavIcons.christmas`): casa con el techo nevado, bastones de caramelo cruzados, dos muñecos de nieve con sombrero, y un regalo con moño. Los íconos de los dos temas están revisados renderizados a 120 y a 24 px, junto con los fondos a tamaño de teléfono.
- Para agregar un tema: el spec en `app_themes.dart`, su precio en `THEME_PRICES` (y desplegar `purchaseTheme`), nombre y descripción en los dos `.arb`, y el `case` en `lib/features/shop/theme_shop_section.dart`. Si trae un fondo propio, es un valor más de `AppBackdrop` y su caso en el constructor de transiciones de `starfield_backdrop.dart`; si cambia la letra, se elige con `headingFace`. Para verlo sin comprarlo, en debug: `flutter run --dart-define=PREVIEW_THEME=<id>`.

**Compra de monedas — bloqueada por las tiendas**

- [ ] Sigue en "Próximamente": el paquete `in_app_purchase` está instalado y el cliente ya escucha compras desde el inicio de sesión, pero no hay productos configurados.
- [x] Verificación del recibo en `verifyCoinPurchase` para **Google Play** (escrita el 2026-10-14, sin desplegar ni probar contra Play):
  - Consulta el token con la Play Developer API (`purchases.products.get`) y solo acredita si Play dice pagado; un pago pendiente espera.
  - Registra cada token en `coin_purchases/{hash del token}`, así que un token acredita a una sola cuenta una sola vez. Si la misma cuenta vuelve a preguntar, se le confirma sin volver a pagar; otra cuenta con el mismo token es rechazada.
  - Cualquier fallo deja la compra pendiente para que la tienda la reentregue en el próximo arranque.
  - La lógica está en `functions/src/coin_purchases.ts`, con tests. **App Store** sigue cerrado: necesita la clave de la App Store Server API, que sale con la membresía de Apple.
- [ ] Faltan pasos que dependen de las cuentas del punto 4:
  - Crear en Play Console (y App Store Connect) los cuatro productos consumibles con los ids de `EconomyService.coinPacks`: `coins_pack_small`, `coins_pack_ai_topic`, `coins_pack_medium`, `coins_pack_large`.
  - En Play Console → **Usuarios y permisos**, invitar a la cuenta de servicio de las funciones con permiso para ver datos financieros y pedidos. Debería ser `1049545801330-compute@developer.gserviceaccount.com`, la predeterminada de las funciones de 2.ª generación; confírmalo en Cloud Run, en el detalle de `verifycoinpurchase`. Sin esto Play responde 401/403 y las compras quedan pendientes, sin perderse.
  - Desplegar `verifyCoinPurchase` y probar una compra de prueba con una cuenta de *license tester*. Esas compras se acreditan, marcadas `test: true` en `coin_purchases`.

**Limpieza antes de lanzar**

- [x] Borradas el 2026-10-15 las dos cuentas de prueba de la tienda, cuyas sesiones se habían perdido: `ClaudeShopTest` (`n2qlwmewl4ZjwmglTCCAQC1gB0r2`) y `ClaudeShopTest2` (`9D2tNE2CiReUKCmSZk47ASjPRS32`). Se borró lo mismo que borra `deleteMyAccount`: `users/{uid}` con sus subcolecciones, `usernames/…` y el usuario de Authentication. Ninguna tenía entradas en clasificaciones, `live_search` ni solicitudes de amistad. Comprobado después: no queda nada de ninguna.
- [ ] Borrar el usuario anónimo `C84wqr2v0JWZvQ7PvK1gf6uxsLD3`, creado el 2026-10-14 desde el emulador de la PC de escritorio al verificar App Check, y las cuentas que creen las pruebas que vengan. **Pospuesto** hasta terminar de agregar temas nuevos: es la sesión del emulador y sirve para probarlos. Desde el 2026-10-15 se llama `ClaudeThemeTest`, para recorrer el tema Espacio: hay que borrar también `usernames/claudethemetest` y su documento en `users`.
- [ ] Borrar también la cuenta de prueba `ClaudePvpBot` (`claudePvpBot0001`), creada el 2026-10-21 desde un script para jugar contra `ClaudeThemeTest` y probar el PvP en vivo en la app: su usuario de Authentication, `users/claudePvpBot0001` y `usernames/claudepvpbot`. Las partidas de prueba que jugaron (`matches/sGe5oJySpuimkdnGN7r4` y su revancha `xRwJeqp9rmWBlJ0V4pxn`, que quedó a medio jugar) se pueden borrar con ellas.

## 7. Revisión factual del banco de preguntas

El 2026-08-07 se completaron los pools de las 9 categorías fijas hasta 100 preguntas cada una (30 fáciles / 40 medias / 30 difíciles = 900 en total). Las 540 nuevas están versionadas en `tools/fill_pools/*.js` y publicadas en Firestore.

- [x] **Revisar la exactitud del banco** (2026-10-10). Se leyeron las 900 preguntas tal como están en Firestore, no solo las 540 nuevas: ninguna tiene el `answerIndex` equivocado, todas tienen cuatro opciones distintas y no hay enunciados duplicados. Se reescribieron siete enunciados flojos sin tocar opciones ni respuesta — cinco que llevaban la respuesta escrita en la pregunta, uno impreciso (atribuía a los Curie el descubrimiento de la radiactividad) y uno discutible (el río más largo del mundo, con el Amazonas entre las opciones). La revisión la hizo Claude leyendo cada pregunta; no sustituye una segunda lectura humana si se quiere certeza total.
- Para corregir una pregunta ya publicada: `node tools/export_questions.js`, marcar la fila con `veredicto = fix` y aplicar con `node tools/apply_question_fixes.js --in=... --commit`. Corrige Firestore y `tools/fill_pools/<categoria>.js` en la misma pasada (el cargador es append-only y se niega a sobrescribir, por diseño).
- El objetivo 30/40/30 no es arbitrario: sale de `FIXED_LEVEL_BANDS` en `functions/src/fixed_level_slicing.ts`. Cada banda necesita 10 preguntas por nivel para que los niveles que la comparten tengan tandas sin solapamiento. Si algún día cambias las bandas, ese objetivo cambia con ellas (hay un test que lo verifica).

## 8. Guardar el progreso con Google o Apple

Todas las cuentas nacen anónimas, y una cuenta anónima se pierde al reinstalar la app o cambiar de teléfono (así se perdió `UserMainTest`). El código para vincularla a Google o Apple ya está (`lib/services/account_link_service.dart`); lo que falta es configuración de consolas, y nada de esto se ha probado todavía contra un inicio de sesión real.

**Android (Google)**

- [x] Habilitar **Google** en Firebase Console → Authentication → Sign-in method (2026-10-10). Al hacerlo se crea el cliente OAuth web que la app necesita.
- [x] Volver a descargar `android/app/google-services.json` después de habilitarlo (2026-10-10); el archivo versionado ya trae los clientes OAuth. Para repetirlo: `firebase apps:sdkconfig ANDROID 1:1049545801330:android:bb4b3946c9eefa6ad18ceb -o android/app/google-services.json`.
- [x] Huellas SHA-1 y SHA-256 de la clave **debug** de la máquina de desarrollo registradas en la app Android de Firebase (2026-10-10).
- [ ] Registrar también las huellas de la **clave de subida** (cuando exista el keystore del punto 4) y de la **clave de firma de Play** (Play Console → Integridad de la app). Sin ellas, el inicio de sesión funciona en debug y falla en la versión de la tienda.
- [ ] Probar en un teléfono: vincular desde Perfil, reinstalar, y recuperar con "Ya tengo una cuenta".

**iOS (Google y Apple)** — bloqueado por la membresía de Apple y por no tener Mac

- [ ] Habilitar **Apple** en Firebase Console → Authentication → Sign-in method.
- [ ] Agregar la capacidad *Sign in with Apple* al target Runner en Xcode.
- [ ] Agregar a `Info.plist` el esquema de URL con el `REVERSED_CLIENT_ID` del `GoogleService-Info.plist` (que hay que volver a descargar tras habilitar Google).
- En Android el botón de Apple no se muestra: requeriría un Service ID de Apple. Quien vincule con Apple en un iPhone no puede recuperar su partida en Android hasta que eso exista.

**Publicación**

- [x] `firebase deploy --only hosting` (2026-10-14). Verificado en https://trivia-ia-app.web.app/privacy.html: la versión en vivo ya explica que vincular la cuenta a Google o Apple es opcional.
- [ ] En el formulario de Data safety de Play, declarar el correo electrónico y el identificador de cuenta como datos opcionales, usados para gestión de la cuenta.

## 9. Cosas ya resueltas en este repo (para tu referencia)

- Metadata cosmética (nombre "TriviaIA" en label/manifest, no el `applicationId` final).
- Firma release por `key.properties` en vez de la debug key (ver punto 4 para lo que falta de tu lado).
- El token FCM ya no se imprime en builds release (`main.dart`): iba a logcat, donde cualquier app con permiso de lectura de logs podía leerlo.
- Política de privacidad y términos de servicio (`public/privacy.html`, `public/terms.html`) + links desde Perfil.
- Eliminar cuenta desde la app (Perfil → Zona peligrosa) + Cloud Function `deleteMyAccount`.
- Firebase App Check inicializado en el cliente (falta el registro en consola, ver punto 2).
- Firebase Crashlytics habilitado (captura errores de Flutter y errores async no capturados).
- CI básico en GitHub Actions (`.github/workflows/ci.yml`): `flutter analyze` + `flutter test` + lint/build de `functions/`.
- Tests iniciales para lógica crítica: `life_service` (regeneración de vidas, gracia para jugadores nuevos), `pvp_league_service` y `league_service` (umbrales de liga).
- Manejo explícito de `stop_reason: "refusal"` en la generación de preguntas con IA (mensaje claro en vez del genérico).

Del 2026-10-12 al 14, encontrado al revisar la tienda y recorrer la app con los temas nuevos:

- La tienda ya carga donde no hay tienda de pagos (web, escritorio): antes se quedaba en un spinner y no mostraba ni los temas. Muestra además el saldo de monedas del jugador.
- Aviso falso de "la acción tardó demasiado": salía a los 12 segundos de estar en cualquier pantalla abierta desde Inicio, aunque todo fuera bien.
- Reabrir un nivel de Solo ya enviado reenviaba la misma partida sin mostrar preguntas, sumaba XP cada vez y dejaba un nivel reprobado imposible de repetir. Corregido en `submitSoloLevelResult`. Una sesión guardada antes del arreglo puede saltar al resultado una vez más y luego queda limpia.
- Tras reprobar un nivel, la pantalla de resultados ofrecía "Continuar (Nivel 2)", que terminaba en "nivel bloqueado". Ahora ofrece reintentar.
- Inicio no mostraba las vidas gastadas en un nivel jugado desde otra pestaña.
- Títulos de barra cortados con puntos suspensivos en teléfono: ahora se encogen para caber, y las pestañas principales muestran solo el avatar en pantallas de menos de 400 px de ancho.
- Desbordes de layout en la tarjeta de vidas de Inicio y en la pestaña Recompensas de la temporada PvP.
- Textos que salían en inglés con la app en español: compra cancelada o fallida, "+80 coins" y "best 1200 MMR" en la temporada PvP.
- La etiqueta del marco equipado en el Perfil ("Marco de Plata") casi no se leía en los temas claros: iba en el color del marco sobre una pastilla de ese mismo color. Corregido para los seis marcos; comprobado por test de contraste, no en pantalla.
- Los nombres de liga tenían el mismo problema: en los temas claros, Silver y Gold quedaban demasiado pálidos sobre su propio tinte (hasta 3.8:1, con 4.5 como mínimo), y en Noche los violetas oscuros apenas se distinguían. Corregido el 2026-10-14 en todos los sitios donde se escribe un nombre de liga: la insignia (Temporada PvP, Weekly Challenge), la tarjeta de liga del Perfil, el menú de partidas en vivo, la búsqueda de rival y la clasificación del Daily Challenge. El texto conserva el tono de la liga y solo se oscurece o aclara lo necesario; un test exige 4.5:1 a cada liga, PvP y semanal, en los seis temas. Tampoco se vio en pantalla.
