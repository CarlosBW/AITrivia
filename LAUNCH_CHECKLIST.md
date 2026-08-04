# Checklist de lanzamiento — TriviaIA

Este documento cubre lo que **queda pendiente y no se puede resolver con código** — son acciones manuales en consolas/cuentas que solo tú puedes hacer. Todo lo demás (código, tests, CI, políticas legales, App Check, Crashlytics, eliminación de cuenta) ya está resuelto en este repo.

**Estado actual:** todo lo que no depende de las cuentas de las tiendas está cerrado. Lo único que falta de verdad son los puntos 2 (parte final) y 4 — ambos bloqueados hasta que gestiones las cuentas de Play Console y App Store Connect, como acordamos dejar para el final.

## 1. Deploy pendiente

- [x] `firebase deploy --only hosting` — hecho, `public/privacy.html` y `public/terms.html` están en vivo con el nombre legal correcto (Massive Dynamics Peru S.A.C.).
- [x] `npm run deploy` en `functions/` — hecho, `deleteMyAccount` y el manejo de `refusal` ya están en producción.

## 2. Firebase App Check (protección contra bots/clientes modificados)

El cliente Flutter ya activa App Check (`main.dart`), pero **no hace nada hasta que lo registres**. Se divide en dos partes porque el registro depende del `applicationId`/bundle ID final:

- [x] Habilitar la **Play Integrity API** en Google Cloud Console (proyecto `trivia-ia-app`) — a nivel de proyecto, no depende del package name, ya se puede hacer.
- [ ] **Junto con el punto 4** (cuando definamos el `applicationId`/bundle ID real): registrar la app Android con Play Integrity y la app iOS con App Attest en Firebase Console → App Check. Hacerlo ahora contra el placeholder `com.example.*` significaría rehacerlo después.
- [ ] Una vez registrado y verificado que la app real está mandando tokens válidos, **recién ahí** activa "Enforce" en Firestore y en Cloud Functions. Si activas "Enforce" antes de registrar la app, bloqueas a todos los usuarios reales.
- [ ] Web no está cubierto todavía (necesita una site key de reCAPTCHA) — si vas a lanzar la versión web, avísame y lo agrego.

## 3. Control de gasto en IA (dinero real desde el 2026-08-04)

Hasta que la API key de Anthropic quedó válida (2026-08-04), el gasto era estructuralmente cero. Ya no. Como el login es anónimo e ilimitado y cada cuenta nueva trae un pase gratis, existe un camino de "cualquiera con el app" a gasto real.

- [x] **Tope diario en el servidor** (`functions/src/ai_budget.ts`): 5000 niveles/día a nivel proyecto (≈500 temas completos, ≈$25 USD/día en el peor caso) y 50/día por cuenta. Sugerencias de títulos tienen su propio medidor (2000/día global, 30/día por cuenta). Contadores en `ai_usage/{fecha}`, con fecha del servidor y transacción, así que ni el reloj del cliente ni dos llamadas simultáneas los saltan. Para cambiar los topes: `AI_METER_CAPS` en ese archivo, y redesplegar.
- [ ] **Alerta de presupuesto en Google Cloud** (pendiente, tuya): Console → Billing → Budgets & alerts → Create budget, alcance el proyecto `trivia-ia-app`, con alertas al 50/90/100%. El tope del servidor acota el peor caso pero no te *avisa*; esto sí.
- [ ] **Límite de gasto en Anthropic Console** (pendiente, tuya): Settings → Limits, define un tope mensual. Es la única defensa que no depende de que nuestro código se comporte.
- Referencia de costo: ~$0.03–0.05 USD por tema completo de 10 niveles con Haiku 4.5.
- Nota: el enforcement de App Check (punto 2) es la solución de fondo a este riesgo — los topes son un paliativo mientras siga bloqueado por las cuentas de las tiendas.

## 4. Cuentas de las tiendas (fuera de alcance por ahora, como acordamos)

- [ ] Play Console: crear la app, definir `applicationId` real (hoy es `com.example.trivia_ia_flutter`), generar keystore de release.
- [ ] App Store Connect: crear la app, definir bundle ID real (hoy es `com.example.triviaIaFlutter`).
- [ ] Una vez tengas los IDs reales, hay que regenerar `google-services.json` / `GoogleService-Info.plist` con `flutterfire configure`.
- [ ] **Junto con esto:** registrar App Check en Firebase Console (ver punto 2) — usa el mismo `applicationId`/bundle ID que se define aquí.
- [ ] Formulario de "Data Safety" (Google Play) y "Privacy Nutrition Label" (Apple) — usa el contenido de `public/privacy.html` como base.

## 5. Revisión legal — guía entregada

- [x] `public/privacy.html` y `public/terms.html` son un borrador funcional basado en lo que la app realmente recolecta (cuenta anónima, progreso de juego, amigos, notificaciones push, títulos de temas de IA enviados a Anthropic), ya con el nombre legal correcto (Massive Dynamics Peru S.A.C.). **No reemplaza asesoría legal.** Puntos específicos a llevarle a un abogado: la sección de ley aplicable (hoy asume Perú), necesidad de lenguaje GDPR si vas a tener usuarios en la UE, la cláusula de privacidad de menores, y (más adelante) la de reembolsos cuando actives compras dentro de la app. Si tu empresa ya tiene abogado/notario de la constitución, es el candidato natural para esta revisión.

## 6. Monetización (Coin Shop)

- [ ] Sigue en "Coming soon" — el paquete `in_app_purchase` está instalado pero no hay productos configurados. Esto depende de tener las cuentas de Play Console/App Store Connect del punto 4, así que no se puede cerrar antes de eso. Cuando tengas las cuentas, dime y conectamos los productos reales.

## 7. Cosas ya resueltas en este repo (para tu referencia)

- Metadata cosmética (nombre "TriviaIA" en label/manifest, no el `applicationId` final).
- Política de privacidad y términos de servicio (`public/privacy.html`, `public/terms.html`) + links desde Perfil.
- Eliminar cuenta desde la app (Perfil → Zona peligrosa) + Cloud Function `deleteMyAccount`.
- Firebase App Check inicializado en el cliente (falta el registro en consola, ver punto 2).
- Firebase Crashlytics habilitado (captura errores de Flutter y errores async no capturados).
- CI básico en GitHub Actions (`.github/workflows/ci.yml`): `flutter analyze` + `flutter test` + lint/build de `functions/`.
- Tests iniciales para lógica crítica: `life_service` (regeneración de vidas, gracia para jugadores nuevos), `pvp_league_service` y `league_service` (umbrales de liga).
- Manejo explícito de `stop_reason: "refusal"` en la generación de preguntas con IA (mensaje claro en vez del genérico).
