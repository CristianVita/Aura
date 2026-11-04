# CONTEXT PROIECT: Aura

## Tehnologii folosite:
- Framework: Flutter
- Limbaj: Dart
- Target principal: Android; suport și pentru Windows. Rate de refresh până la 144 Hz, în limita ecranului și a politicilor sistemului.

## Reguli de stil și cod:
- Folosește clean architecture și separă logica de UI (State Management).
- Toate șirurile de text vizibile în UI trebuie să fie pregătite pentru localizare.
- Când generezi cod, oferă doar modificările necesare sau funcțiile întregi, fără să rescrii tot fișierul de la zero dacă nu este cerut.
- Menține comentariile în cod scurte și doar unde este strict necesar.
- Mereu verifică acest fișier pentru updates și reguli noi.
- Când știi ce urmează de făcut, apucă-te direct

## Stadiu curent / TODO:
- [x] Suport 144Hz implementat și optimizat.
- [x] Clonare structură meniuri din aplicația originală.
- [x] Backup și restaurare, cu previzualizare și recuperare după erori.
- [x] Setări de redare, căști și notificări media.
- [x] Temă, font și culori: sistem/luminos/întunecat/OLED, accente, font și dimensiunea textului; preferințe incluse în backup.
- [x] Navigare și ecran de pornire configurabile: ordine, file opționale, etichete și pagina inițială a colecției; incluse în backup.
- [ ] Configurarea paginilor bibliotecii, albumelor și artiștilor.
- [ ] Descărcări offline și cache pentru sursele de pe server.
- [ ] De implementat: Adaptarea aplicației pentru toate limbile (global translation).
- Localizare existentă: paginile de aspect și navigare folosesc ARB ro/en și delegați Flutter; celelalte ecrane trebuie migrate.
- [ ] De revizuit: Implementarea unei logici de a importa si folosi poze de cover pentru albume in momentul in care se asculta o piesa cu un album specificat; poza poate fi preluata local de pe device-ul respectiv, sau de pe un server / google foto
- [x] Sigla Aura din aplicație are fundal adaptat temei și desen în culoarea de accent; comună antetului și ferestrei Despre Aura.

## Siguranța datelor
- Respectă AGENTS.md: fără dezinstalarea sau ștergerea datelor aplicației live și fără teste Android de integrare sub ID-ul ei.
- Actualizările pe telefon folosesc `adb install -r`, după copia locală a metadatelor. Datele personale nu se trimit pe GitHub.
