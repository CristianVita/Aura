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

## Stadiu curent / TODO:
- [x] Suport 144Hz implementat și optimizat.
- [x] Clonare structură meniuri din aplicația originală.
- [x] Backup și restaurare, cu previzualizare și recuperare după erori.
- [x] Setări de redare, căști și notificări media.
- [x] Temă, font și culori: sistem/luminos/întunecat/OLED, accente, font și dimensiunea textului; preferințe incluse în backup.
- [x] Navigare și ecran de pornire configurabile: ordine, file opționale, etichete și pagina inițială a colecției; incluse în backup.
- [x] Configurarea paginilor Bibliotecă/Album/Artist: categorii, ordine, coloane, listă/grilă, sortare și rezumat; preferințe incluse în backup.
- [ ] Descărcări offline și cache pentru sursele de pe server.
- [x] Redenumirea fișierelor audio locale pe Android și Windows: apăsare lungă pe piesă → Redenumește fișierul audio. Extensia se păstrează, fișierele de pe server nu sunt modificate. Pe Windows piesa nu trebuie să fie în coada activă; referințele salvate sunt migrate și recuperarea este jurnalizată. Pe Android se solicită permisiunea sistemului când este necesar; URI-ul piesei rămâne același. Detalii: `docs/file-renaming.md`.
- [x] Localizare globală: 20 de limbi incluse offline, selectabile din Setări → Traduceri, cu schimbare imediată și opțiunea de a urma limba sistemului.
- Ecranele, dialogurile, erorile și comenzile media folosesc resurse ARB. Sunt localizate pluralurile, datele și numerele; araba folosește afișare de la dreapta la stânga. Titlurile pieselor și celelalte metadate personale rămân nemodificate.
- [ ] Revizie lingvistică de către vorbitori nativi pentru pachetul extins; traducerile suplimentare au pornit din schițe asistate automat, cu revizie manuală a comenzilor principale.
- [ ] De revizuit: Implementarea unei logici de a importa si folosi poze de cover pentru albume in momentul in care se asculta o piesa cu un album specificat; poza poate fi preluata local de pe device-ul respectiv, sau de pe un server / google foto
- [x] Sigla Aura din aplicație are fundal adaptat temei și desen în culoarea de accent; comună antetului și ferestrei Despre Aura.
- [x] Limbă nativă aleasă explicit la prima configurare, salvată separat de limba interfeței și modificabilă din Setări → Traduceri. Instalațiile existente o aleg o singură dată după actualizare. Backupurile importate nu o înlocuiesc.
- [x] Protecție la schimbarea limbii: dialog DA/NU întotdeauna în limba nativă și direcția ei, temporizator de 5 secunde și revenire automată la limba nativă. NU, Back, atingerea în afara dialogului sau trecerea în fundal anulează schimbarea; numai DA păstrează limba nouă. Previzualizările nu ajung în salvări concurente sau backupuri.
- [ ] Completare meniu aplicatie, clonand meniul si butoanele aplicatiei Symfonium
- [ ] Continuarea setărilor avansate de performanță și completarea opțiunilor suplimentare pentru paginile configurabile, după necesitate.
- [ ] Implementare "fisiere offline" si "fisiere generale
- [x] Dialogul de confirmare a limbii este afișat după randarea interfeței în limba selectată; confirmarea rămâne în limba nativă.



## Actualizare — 6 noiembrie 2026
- Pagina Acasă permite afișarea sau ascunderea secțiunilor favorite și ascultate recent.
- Setările paginii Căutare permit alegerea câmpurilor implicite și a filtrului de favorite; acestea se păstrează și se includ în backupul opțional al setărilor.
- Pagina Playlist permite sortarea listei și afișarea opțională a numărului de piese, fără a schimba ordinea pieselor din playlisturi.
- Pagina Genuri grupează piesele după metadate și permite listă/grilă, sortare, coloane și rezumat. Bibliotecile locale existente necesită rescanare, iar sursele Navidrome necesită reîmprospătare. Pe Android sub versiunea 11 genurile locale rămân necunoscute; pe Windows se folosește primul gen din metadate.
- Pentru Căutare rămâne activ cel puțin un câmp; filtrele pot fi modificate temporar pe ecran. Pentru Playlist sortarea este după ordinea inițială, nume sau numărul de piese. Setările celor două pagini se salvează, pot fi resetate independent și participă la restaurarea opțională a setărilor din backup.
- Validare locală pentru schimbările curente: 125 teste Flutter trecute, `flutter analyze` fără probleme și compilări Android ARM64 și Windows x64 release reușite. Redenumirea a fost testată pe fișiere sintetice pe Windows și pe Android într-o aplicație de test separată; pagina Genuri nu a fost testată pe dispozitiv.
- Stare livrare: setările Căutare, Playlist, Genuri și redenumirea sunt instalate pe telefon și în pachetul Windows portabil. După instalarea pe telefon au fost verificate biblioteca, ratingul vizibil și coada; dialogul de redenumire a fost deschis și anulat fără a modifica o piesă personală. Codul local include ulterior o protecție suplimentară pentru repetarea cererii de permisiune pe Android 10, care nu este în APK-ul instalat pe telefonul Android 14.
- În timpul primei încercări de test Android, Flutter a reconstruit și instalat accidental varianta debug sub ID-ul aplicației normale, deși fusese verificat în prealabil un APK de test separat. Instalarea normală a fost restaurată, spațiul ei de date a rămas același, iar bibliotecă, date muzicale și coadă au fost salvate complet local înainte de restaurare. Protecția Gradle recunoaște acum și punctele de intrare temporare `flutter_test_listener`; ID-ul rezultat a fost verificat ca `.integration`.
- La actualizarea anterioară, backupul Android standard a fost gol; exportul Aura a acoperit datele organizate și setările, dar nu biblioteca internă și coada. Ulterior au fost salvate local copii complete ale celor trei fișiere de metadate.

## Rezumat actualizat — 4 noiembrie 2026
- Etapele recente includ sigla vectorială adaptată temei, setările de aspect, navigarea configurabilă și paginile de bibliotecă/albume/artiști cu listă, grilă și sortare.
- Pachetul de localizare include română, engleză, franceză, germană, spaniolă, italiană, portugheză, rusă, ucraineană, poloneză, neerlandeză, turcă, arabă, hindi, chineză simplificată, japoneză, coreeană, indoneziană, vietnameză și thailandeză.
- Limba curentă și limba nativă se salvează separat. Sistemul oferă limba inițială pentru ecranul de configurare, cu engleză ca rezervă; utilizatorul alege apoi explicit limba nativă. Confirmările și anulările folosesc mereu limba nativă, inclusiv după mai multe schimbări succesive.
- Validare: 111 teste automate trecute și analiză fără probleme, dintre care 14 teste de localizare. Acoperă alegerea inițială, persistența limbii native, confirmări, salvări eșuate, pluraluri, RTL, expirarea la 5 secunde, anularea lângă expirare, revenirea din fundal și japoneză → coreeană → română nativă.
- Verificarea catalogelor a eliminat marcajele de tokenizare rămase în cinci limbi și a adăugat o verificare automată împotriva reapariției lor. Au fost corectate și etichete de meniu în japoneză/chineză; revizia lingvistică completă rămâne în TODO.
- Au fost generate versiuni release Android ARM64 și Windows x64. Pe OnePlus 8T au fost verificate schimbarea imediată română/engleză/arabă și orientarea RTL; aplicația a fost readusă în română. Biblioteca de 153 de piese, ratingul existent și coada pusă pe pauză au rămas prezente.
- Verificări suplimentare pe telefon: alegerea inițială a românei native, confirmarea japonezei și japoneză → coreeană cu dialog în română și revenire automată la româna nativă. Au fost verificate și afișarea chinezei și confirmările japoneze pe etapa anterioară a fluxului.
- Detalii și limite lingvistice: `docs/localization.md`. Descărcările offline/cache, importul de coperte și revizia traducerilor extinse rămân de continuat.
- Repository-ul `https://github.com/CristianVita/Aura` a fost făcut public la cererea utilizatorului; accesul fără autentificare a fost verificat. Versiunile validate rămân Android și Windows; iOS nu are încă o versiune distribuibilă.

## Siguranța datelor
- Respectă AGENTS.md: fără dezinstalarea sau ștergerea datelor aplicației live și fără teste Android de integrare sub ID-ul ei.
- Actualizările pe telefon folosesc `adb install -r`, după copia locală a metadatelor. Datele personale nu se trimit pe GitHub.
