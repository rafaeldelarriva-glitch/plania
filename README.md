# PlanIA

Agenda privada responsive con React + Vite, Supabase y Vercel.

## Desarrollo

```sh
npm ci
npm test
npm run dev
npm run build
```

La única configuración cliente incluida es la URL y clave **publicable** de Supabase. Las contraseñas SMTP se cifran en la función del servidor; ninguna clave service-role forma parte del frontend.

## Funcionalidad inicial

- Login, registro pendiente de aprobación y recuperación; administrador inicial por identidad de correo verificada del propietario.
- Escritorio con accesos editables y favicon automático, búsqueda de eventos y nombres de adjuntos.
- Agenda día/semana/mes, edición, duplicación, recurrencias materializadas, guardias con horario habitual y arrastre en escritorio.
- Vacaciones/asuntos por año: días naturales sin festivos, sin duplicar fechas solapadas; cancelados y papelera excluidos.
- Archivos privados por usuario, enlaces, papelera recuperable, informes y exportación iCalendar/Excel/PDF mediante impresión.
- Importación .ics con revisión y detección de duplicados. Las series recurrentes externas deben expandirse antes de importar.
- Administración de acceso, bloqueo con revocación de sesiones, roles, recuperación de contraseña, eliminación y registro de acciones.
- Avisos segmentados/programados, campana, consultas y respuestas.
- SMTP personal cifrado, correo de prueba, recordatorios y resumen diario con cron de servidor.
- Segundo factor TOTP, PWA con caché limitada a recursos públicos; la agenda requiere conexión.

## Operación

`database/schema.sql` y `database/services.sql` documentan el esquema inicial aplicado al proyecto separado de PlanIA. No volver a ejecutar sobre una base inicializada. El proyecto Supabase es `plmlusinojpnkqckqdxo` y la función es `plania-service`.

El cron `plania-notifications` procesa cada minuto recordatorios y avisos. La configuración del trabajo se conserva en la base; la función valida la credencial del trabajador por separado del JWT de usuario. Los endpoints de usuario validan la sesión con Auth y el estado de la cuenta. Los envíos SMTP tienen hasta tres intentos y registro por usuario. Revisar `cron.job_run_details`, `net._http_response` y `delivery_log` al operar.

## Configuración que requiere al propietario

- Registrar `rafael.delarriva@gmail.com`, confirmar identidad y elegir contraseña. No se crea una contraseña compartida.
- Configurar en Supabase Auth la URL de la aplicación y URLs de retorno permitidas para confirmaciones y recuperación. El correo Auth de prueba de Supabase tiene límites; usar SMTP de producción antes de invitar usuarios.
- Activar TOTP en Mi perfil → Seguridad.
- Configurar y probar SMTP personal; sin credenciales reales no se verifica la entrega de correo.
- Importar/revisar festivos nacionales, autonómicos y locales. La ubicación no descarga calendarios oficiales automáticamente.

## Límites de la primera versión

Los cambios de serie conservan las fechas individuales; título, tipología, notas, enlaces, avisos y estado se propagan, pero un cambio de horario afecta a la aparición seleccionada. Los eventos se conservan en papelera hasta eliminación manual. La exportación Excel incluye eventos solapados con el intervalo con su duración completa, explicitado en la hoja Resumen. PDF usa Guardar como PDF del navegador e incluye anexo de detalle. Zona horaria de pantalla: la del dispositivo.

Antes de uso general, completar prueba de registro/confirmación/correo con la cuenta propietaria y comprobar el flujo en dispositivos reales.
