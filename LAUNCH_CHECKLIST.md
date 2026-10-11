# Checklist de lanzamiento — TriviaIA

Este documento cubre lo que **queda pendiente y no se puede resolver con código** — son acciones manuales en consolas/cuentas que solo tú puedes hacer. Todo lo demás (código, tests, CI, políticas legales, App Check, Crashlytics, eliminación de cuenta) ya está resuelto en este repo.

**Estado actual (2026-08-07):** todo lo que no depende de las cuentas de las tiendas está cerrado. Lo que falta se reduce a tres cosas:

1. Los puntos **2 (parte final)** y **4**, bloqueados hasta que gestiones Play Console y App Store Connect.
2. La **revisión legal** del punto 5 — de contenido, no de código. (La revisión factual del banco, punto 7, quedó hecha el 2026-10-10.)
3. **Web** (punto 2, último ítem) solo si vas a lanzar esa plataforma.

## 1. Deploy pendiente

- [x] `firebase deploy --only hosting` — hecho, `public/privacy.html` y `public/terms.html` están en vivo con el nombre legal correcto (Massive Dynamics Peru S.A.C.).
- [x] `npm run deploy` en `functions/` — hecho, `deleteMyAccount` y el manejo de `refusal` ya están en producción.
- [x] `firebase deploy --only firestore:indexes` (2026-08-07) — los 16 índices ya estaban en vivo, pero los dos `fieldOverrides` de collection-group (`sent_friend_requests.targetUid`, `friend_requests.requesterUid`) nunca se habían desplegado: `--only firestore:rules` no toca índices, y son deploys separados. Sin ellos, la limpieza de espejos de solicitudes de amistad en `deleteMyAccount` fallaba en silencio. Verificado que ambos terminaron de construirse ejecutando las queries reales contra producción.

## 2. Firebase App Check (protección contra bots/clientes modificados)

El cliente Flutter ya activa App Check (`main.dart`), pero **no hace nada hasta que lo registres**. Se divide en dos partes porque el registro depende del `applicationId`/bundle ID final:

- [x] Habilitar la **Play Integrity API** en Google Cloud Console (proyecto `trivia-ia-app`) — a nivel de proyecto, no depende del package name, ya se puede hacer.
- [x] Habilitar la **Firebase App Check API** (2026-08-07). Es **distinta** de la Play Integrity API: aquella es el proveedor que atestigua el dispositivo, esta es el servicio que emite y valida los tokens. Estuvo deshabilitada mientras la otra ya estaba lista, así que App Check emitía un token placeholder en silencio en vez de fallar de forma visible. Se detectó por el `403 ... App Check API has not been used in project` en el log de la app.
- [ ] Registrar el **token de depuración** del emulador (Firebase Console → App Check → app Android → ⋮ → Manage debug tokens). Opcional hasta activar *enforce*, y habrá que rehacerlo cuando cambie el `applicationId`; hasta entonces el log muestra `App attestation failed`, que es App Check validando correctamente contra una lista vacía.
- [ ] **Junto con el punto 4** (cuando definamos el `applicationId`/bundle ID real): registrar la app Android con Play Integrity y la app iOS con App Attest en Firebase Console → App Check. Hacerlo ahora contra el placeholder `com.example.*` significaría rehacerlo después.
- [ ] Una vez registrado y verificado que la app real está mandando tokens válidos, **recién ahí** activa "Enforce" en Firestore y en Cloud Functions. Si activas "Enforce" antes de registrar la app, bloqueas a todos los usuarios reales.
- [ ] Web no está cubierto todavía (necesita una site key de reCAPTCHA) — si vas a lanzar la versión web, avísame y lo agrego.

## 3. Control de gasto en IA (dinero real desde el 2026-08-04)

Hasta que la API key de Anthropic quedó válida (2026-08-04), el gasto era estructuralmente cero. Ya no. Como el login es anónimo e ilimitado y cada cuenta nueva trae un pase gratis, existe un camino de "cualquiera con el app" a gasto real.

- [x] **Tope diario en el servidor** (`functions/src/ai_budget.ts`): 5000 niveles/día a nivel proyecto (≈500 temas completos, ≈$15 USD/día en el peor caso con el costo medido abajo) y 50/día por cuenta. Sugerencias de títulos tienen su propio medidor (2000/día global, 30/día por cuenta). Contadores en `ai_usage/{fecha}`, con fecha del servidor y transacción, así que ni el reloj del cliente ni dos llamadas simultáneas los saltan. Para cambiar los topes: `AI_METER_CAPS` en ese archivo, y redesplegar.
- [x] **Alerta de presupuesto en Google Cloud** (2026-08-07, recreada el 2026-10-11): presupuesto mensual de S/25 sobre el proyecto `trivia-ia-app`, con alertas al 50/90/100%. Los presupuestos pertenecen a la cuenta de facturación, no al proyecto: la original estaba en la cuenta de prueba, que venció el 2026-09-09 y dejó el proyecto sin facturación — y la app caída — hasta el 2026-10-10. La actual está en la cuenta `Massive Dynamics Peru S.A.C.` (`01E279-5EDCFD-649EF4`) y avisa a sus administradores, `cbalcazarwong@gmail.com` y `apps@massivedynamics.pe`. Si algún día se cambia de cuenta de facturación, hay que volver a crearla. Dos límites que conviene tener presentes: **solo notifica, no corta** (la columna "Spend cap status" dice "Not applicable" — los presupuestos de Cloud Billing nunca detienen el gasto), y **no ve el gasto de Anthropic**, porque las funciones llaman a la API de primera parte (`new Anthropic({apiKey})`), que Anthropic factura aparte. Cubre Firestore, Functions y hosting, que es el gasto barato.
- [x] **Techo duro del gasto en IA**: la cuenta de Anthropic funciona con créditos prepagados y la **recarga automática está desactivada** (verificado 2026-08-07), así que el saldo cargado es el tope real y no se puede gastar de más. Con ~$25 de saldo y un peor caso de ~$15/día, eso es algo más de un día de abuso máximo antes de que la API deje de responder.
- [x] **Límite de gasto en Anthropic Console** (2026-10-10): USD 100 al mes, en Facturación → Límites de gasto. El valor por defecto era USD 200 000, que no protegía de nada. Es el segundo freno, detrás del saldo prepagado: si algún día se activa la recarga automática, pasa a ser el único.
- Nota sobre el fallo por saldo agotado: `createAiTopic` **cobra después de generar** (`index.ts`: genera en ~6424, cobra en la transacción de ~6458), así que si Claude falla por falta de créditos el jugador no pierde monedas ni su pase gratis. La degradación es limpia: deja de poder crear temas IA, y el resto del juego (solo, PvP, diario, semanal) no toca Anthropic.
- Referencia de costo, **medida** el 2026-10-10 con Haiku 5.5: USD 0.04 por 14 generaciones de 10 preguntas, o sea ~$0.003 por nivel y ~$0.03 por tema completo de 10 niveles. Es el extremo bajo de lo que costaba Haiku 4.5 (~$0.03–0.05) y no la décima parte que sugiere el precio por token: Haiku 5.5 razona antes de responder y esos tokens se pagan como salida. Apagar el razonamiento (`thinking: {type: "disabled"}`) lo bajaría a cerca de $0.01 por tema, a cambio de calidad no medida.
- Nota: el enforcement de App Check (punto 2) es la solución de fondo a este riesgo — los topes son un paliativo mientras siga bloqueado por las cuentas de las tiendas.

## 4. Cuentas de las tiendas (fuera de alcance por ahora, como acordamos)

- [ ] Play Console: crear la app, definir `applicationId` real (hoy es `com.example.trivia_ia_flutter`), generar keystore de release.
  - El lado de código ya está listo: `android/app/build.gradle.kts` lee `android/key.properties` (claves `keyAlias`, `keyPassword`, `storeFile`, `storePassword`) y firma release con esa clave. Solo falta crear el keystore y ese archivo — **no lo commitees**, ya está en `.gitignore`. Mientras `key.properties` no exista, el build release cae a la debug key y Gradle lo avisa con un `WARNING`; ese AAB no es publicable en Play.
- [ ] App Store Connect: crear la app, definir bundle ID real (hoy es `com.example.triviaIaFlutter`).
- [ ] Una vez tengas los IDs reales, hay que regenerar `google-services.json` / `GoogleService-Info.plist` con `flutterfire configure`.
- [ ] **Junto con esto:** registrar App Check en Firebase Console (ver punto 2) — usa el mismo `applicationId`/bundle ID que se define aquí.
- [ ] Formulario de "Data Safety" (Google Play) y "Privacy Nutrition Label" (Apple) — usa el contenido de `public/privacy.html` como base.

## 5. Revisión legal — guía entregada

- [x] `public/privacy.html` y `public/terms.html` son un borrador funcional basado en lo que la app realmente recolecta (cuenta anónima, progreso de juego, amigos, notificaciones push, títulos de temas de IA enviados a Anthropic), ya con el nombre legal correcto (Massive Dynamics Peru S.A.C.). **No reemplaza asesoría legal.** Puntos específicos a llevarle a un abogado: la sección de ley aplicable (hoy asume Perú), necesidad de lenguaje GDPR si vas a tener usuarios en la UE, la cláusula de privacidad de menores, y (más adelante) la de reembolsos cuando actives compras dentro de la app. Si tu empresa ya tiene abogado/notario de la constitución, es el candidato natural para esta revisión.

## 6. Monetización (Coin Shop)

- [ ] Sigue en "Coming soon" — el paquete `in_app_purchase` está instalado pero no hay productos configurados. Esto depende de tener las cuentas de Play Console/App Store Connect del punto 4, así que no se puede cerrar antes de eso. Cuando tengas las cuentas, dime y conectamos los productos reales.

## 7. Revisión factual del banco de preguntas

El 2026-08-07 se completaron los pools de las 9 categorías fijas hasta 100 preguntas cada una (30 fáciles / 40 medias / 30 difíciles = 900 en total). Las 540 nuevas están versionadas en `tools/fill_pools/*.js` y publicadas en Firestore.

- [x] **Revisar la exactitud del banco** (2026-10-10). Se leyeron las 900 preguntas tal como están en Firestore, no solo las 540 nuevas: ninguna tiene el `answerIndex` equivocado, todas tienen cuatro opciones distintas y no hay enunciados duplicados. Se reescribieron siete enunciados flojos sin tocar opciones ni respuesta — cinco que llevaban la respuesta escrita en la pregunta, uno impreciso (atribuía a los Curie el descubrimiento de la radiactividad) y uno discutible (el río más largo del mundo, con el Amazonas entre las opciones). La revisión la hizo Claude leyendo cada pregunta; no sustituye una segunda lectura humana si se quiere certeza total.
- Para corregir una pregunta ya publicada: `node tools/export_questions.js`, marcar la fila con `veredicto = fix` y aplicar con `node tools/apply_question_fixes.js --in=... --commit`. Corrige Firestore y `tools/fill_pools/<categoria>.js` en la misma pasada (el cargador es append-only y se niega a sobrescribir, por diseño).
- El objetivo 30/40/30 no es arbitrario: sale de `FIXED_LEVEL_BANDS` en `functions/src/fixed_level_slicing.ts`. Cada banda necesita 10 preguntas por nivel para que los niveles que la comparten tengan tandas sin solapamiento. Si algún día cambias las bandas, ese objetivo cambia con ellas (hay un test que lo verifica).

## 8. Guardar el progreso con Google o Apple

Todas las cuentas nacen anónimas, y una cuenta anónima se pierde al reinstalar la app o cambiar de teléfono (así se perdió `UserMainTest`). El código para vincularla a Google o Apple ya está (`lib/services/account_link_service.dart`); lo que falta es configuración de consolas, y nada de esto se ha probado todavía contra un inicio de sesión real.

**Android (Google)**

- [ ] Habilitar **Google** en Firebase Console → Authentication → Sign-in method. Al hacerlo se crea el cliente OAuth web que la app necesita; hoy `google-services.json` no trae ninguno.
- [ ] Volver a descargar `android/app/google-services.json` después de habilitarlo: `firebase apps:sdkconfig ANDROID 1:1049545801330:android:bb4b3946c9eefa6ad18ceb -o android/app/google-services.json`.
- [x] Huellas SHA-1 y SHA-256 de la clave **debug** de la máquina de desarrollo registradas en la app Android de Firebase (2026-10-10).
- [ ] Registrar también las huellas de la **clave de subida** (cuando exista el keystore del punto 4) y de la **clave de firma de Play** (Play Console → Integridad de la app). Sin ellas, el inicio de sesión funciona en debug y falla en la versión de la tienda.
- [ ] Probar en un teléfono: vincular desde Perfil, reinstalar, y recuperar con "Ya tengo una cuenta".

**iOS (Google y Apple)** — bloqueado por la membresía de Apple y por no tener Mac

- [ ] Habilitar **Apple** en Firebase Console → Authentication → Sign-in method.
- [ ] Agregar la capacidad *Sign in with Apple* al target Runner en Xcode.
- [ ] Agregar a `Info.plist` el esquema de URL con el `REVERSED_CLIENT_ID` del `GoogleService-Info.plist` (que hay que volver a descargar tras habilitar Google).
- En Android el botón de Apple no se muestra: requeriría un Service ID de Apple. Quien vincule con Apple en un iPhone no puede recuperar su partida en Android hasta que eso exista.

**Publicación**

- [ ] `firebase deploy --only hosting` — la política de privacidad y los términos ya mencionan el inicio de sesión opcional, pero la versión en vivo todavía dice que la cuenta es solo anónima.
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
