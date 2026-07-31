# Checklist de lanzamiento — TriviaIA

Este documento cubre lo que **queda pendiente y no se puede resolver con código** — son acciones manuales en consolas/cuentas que solo tú puedes hacer. Todo lo demás (código, tests, CI, políticas legales, App Check, Crashlytics, eliminación de cuenta) ya está resuelto en este repo.

## 1. Deploy pendiente

- [ ] Correr `firebase deploy --only hosting` (o `firebase deploy` completo) para publicar `public/privacy.html` y `public/terms.html`. No pude hacerlo desde esta sesión porque `firebase-tools` no está autenticado aquí.
- [ ] Correr `npm run deploy` en `functions/` para publicar `deleteMyAccount`, el manejo de `refusal` en la generación de IA, y el resto de cambios de esta sesión.

## 2. Firebase App Check (protección contra bots/clientes modificados)

El cliente Flutter ya activa App Check (`main.dart`), pero **no hace nada hasta que lo registres**:

- [ ] Firebase Console → App Check → registrar la app Android con **Play Integrity API** (necesitas habilitar esa API en Google Cloud Console primero) y la app iOS con **App Attest**.
- [ ] Una vez registrado y verificado que la app real está mandando tokens válidos (puedes verlo en la consola), **recién ahí** activa "Enforce" en Firestore y en Cloud Functions. Si activas "Enforce" antes de registrar la app, bloqueas a todos los usuarios reales.
- [ ] Web no está cubierto todavía (necesita una site key de reCAPTCHA) — si vas a lanzar la versión web, avísame y lo agrego.

## 3. Alertas de presupuesto (gasto real de dinero ahora)

- [ ] Google Cloud Console → Billing → Budgets & alerts: configura una alerta sobre el proyecto `trivia-ia-app` (plan Blaze).
- [ ] Consola de Anthropic → configura límites de gasto/alertas para la API key de `ANTHROPIC_API_KEY`.

## 4. Cuentas de las tiendas (fuera de alcance por ahora, como acordamos)

- [ ] Play Console: crear la app, definir `applicationId` real (hoy es `com.example.trivia_ia_flutter`), generar keystore de release.
- [ ] App Store Connect: crear la app, definir bundle ID real (hoy es `com.example.triviaIaFlutter`).
- [ ] Una vez tengas los IDs reales, hay que regenerar `google-services.json` / `GoogleService-Info.plist` con `flutterfire configure`.
- [ ] Formulario de "Data Safety" (Google Play) y "Privacy Nutrition Label" (Apple) — usa el contenido de `public/privacy.html` como base.

## 5. Revisión legal

- [ ] `public/privacy.html` y `public/terms.html` son un borrador funcional basado en lo que la app realmente recolecta (cuenta anónima, progreso de juego, amigos, notificaciones push, títulos de temas de IA enviados a Anthropic). **No reemplaza asesoría legal** — recomendamos que un abogado los revise antes del lanzamiento, especialmente la sección de ley aplicable (hoy asume Perú) y cualquier requisito GDPR si vas a tener usuarios en la Unión Europea.

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
