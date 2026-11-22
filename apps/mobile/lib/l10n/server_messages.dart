// Messages d'erreur renvoyés par l'API (en français) : leur version simple dans la langue du membre.
// L'API répond toujours en français ; c'est l'app qui traduit, pour toutes les langues, y compris en
// donnant en français une phrase plus simple que celle du serveur.
// Message inconnu de cette table : il s'affiche tel que le serveur l'a écrit.
// Swahili et lingala : à faire relire par des locutrices avant le pilote.
// ignore_for_file: lines_longer_than_80_chars

import 'l10n.dart';

/// Texte simple : français, swahili, lingala, anglais.
typedef _Says = ({String fr, String sw, String ln, String en});

const Map<String, _Says> _exact = {
  // Connexion
  'Code invalide ou expiré.': (
    fr: 'Ce code ne marche pas. Demandez un nouveau code.',
    sw: 'Msimbo huu haufanyi kazi. Omba msimbo mpya.',
    ln: 'Kode oyo esalaka te. Senga kode ya sika.',
    en: 'This code does not work. Ask for a new code.',
  ),
  'Session expirée.': (
    fr: 'Reconnectez-vous, s\'il vous plaît.',
    sw: 'Tafadhali ingia tena.',
    ln: 'Kota lisusu, svp.',
    en: 'Please sign in again.',
  ),
  'Connexion requise.': (
    fr: 'Reconnectez-vous, s\'il vous plaît.',
    sw: 'Tafadhali ingia tena.',
    ln: 'Kota lisusu, svp.',
    en: 'Please sign in again.',
  ),
  'Aucun compte pour ce numéro. Inscrivez-vous.': (
    fr: 'Ce numéro n\'a pas encore de compte. Créez-le.',
    sw: 'Namba hii bado haina akaunti. Ifungue.',
    ln: 'Nimero oyo ezali naino na compte te. Salá yango.',
    en: 'This number has no account yet. Create one.',
  ),
  'Un compte existe déjà pour ce numéro.': (
    fr: 'Ce numéro a déjà un compte. Entrez votre PIN.',
    sw: 'Namba hii tayari ina akaunti. Weka PIN yako.',
    ln: 'Nimero oyo ezali na compte. Koma PIN na yo.',
    en: 'This number already has an account. Enter your PIN.',
  ),
  'Ce compte est bloqué. Contactez le support Mchango.': (
    fr: 'Ce compte est bloqué. Appelez l\'équipe Mchango.',
    sw: 'Akaunti hii imefungwa. Piga simu kwa timu ya Mchango.',
    ln: 'Compte oyo ekangami. Benga équipe ya Mchango.',
    en: 'This account is blocked. Call the Mchango team.',
  ),
  'Vérification du numéro expirée. Demandez un nouveau code.': (
    fr: 'Le temps est passé. Demandez un nouveau code.',
    sw: 'Muda umepita. Omba msimbo mpya.',
    ln: 'Ntango eleki. Senga kode ya sika.',
    en: 'Time is up. Ask for a new code.',
  ),
  'Vérification du numéro déjà utilisée. Demandez un nouveau code.': (
    fr: 'Ce code a déjà servi. Demandez un nouveau code.',
    sw: 'Msimbo huu umeshatumika. Omba msimbo mpya.',
    ln: 'Kode oyo esalelamaki. Senga kode ya sika.',
    en: 'This code was already used. Ask for a new code.',
  ),
  'Appareil non reconnu. Reconnectez-vous avec un code SMS.': (
    fr: 'Ce téléphone n\'est plus reconnu. Reconnectez-vous avec un code SMS.',
    sw: 'Simu hii haitambuliki tena. Ingia tena kwa msimbo wa SMS.',
    ln: 'Telefone oyo eyebani lisusu te. Kota lisusu na kode ya SMS.',
    en: 'This phone is no longer recognised. Sign in again with an SMS code.',
  ),
  'Trop de demandes de code. Réessayez dans quelques minutes.': (
    fr: 'Trop de codes demandés. Attendez quelques minutes.',
    sw: 'Umeomba misimbo mingi. Subiri dakika chache.',
    ln: 'Osengi bakode mingi. Zela miniti moke.',
    en: 'Too many codes requested. Wait a few minutes.',
  ),
  // Rejoindre une tontine
  "Code d'invitation invalide ou expiré.": (
    fr: 'Ce code ne marche pas. Vérifiez les lettres, ou demandez un nouveau code au président.',
    sw: 'Msimbo huu haufanyi kazi. Kagua herufi, au omba msimbo mpya kwa rais.',
    ln: 'Kode oyo esalaka te. Tala mikanda, to senga kode ya sika na mokambi.',
    en: 'This code does not work. Check the letters, or ask the president for a new code.',
  ),
  "Trop d'essais de code d'invitation. Réessayez dans une heure.": (
    fr: 'Trop d\'essais. Réessayez dans une heure.',
    sw: 'Majaribio mengi mno. Jaribu tena baada ya saa moja.',
    ln: 'Bomekami mingi. Meka lisusu sima ya ngonga moko.',
    en: 'Too many tries. Try again in one hour.',
  ),
  'Le groupe est complet.': (
    fr: 'Ce groupe est plein.',
    sw: 'Kikundi hiki kimejaa.',
    ln: 'Lisanga oyo etondi.',
    en: 'This group is full.',
  ),
  'Vous êtes déjà membre de ce groupe.': (
    fr: 'Vous êtes déjà dans ce groupe.',
    sw: 'Tayari uko katika kikundi hiki.',
    ln: 'Ozali kala na lisanga oyo.',
    en: 'You are already in this group.',
  ),
  'Le groupe a déjà démarré : on ne peut plus le rejoindre.': (
    fr: 'Cette tontine a déjà commencé : on ne peut plus entrer.',
    sw: 'Likelemba hii imeshaanza: huwezi kuingia tena.',
    ln: 'Likelemba oyo ebandi kala: okoki kokota lisusu te.',
    en: 'This tontine has already started: you can no longer join.',
  ),
  'Il faut accepter le règlement du groupe pour le rejoindre.': (
    fr: 'Pour entrer, acceptez d\'abord les règles du groupe.',
    sw: 'Ili uingie, kubali kwanza sheria za kikundi.',
    ln: 'Mpo na kokota, ndima liboso mibeko ya lisanga.',
    en: 'To join, first accept the group rules.',
  ),
  'Groupe introuvable.': (
    fr: 'Ce groupe n\'existe pas, ou vous n\'en faites plus partie.',
    sw: 'Kikundi hiki hakipo, au wewe si mwanachama tena.',
    ln: 'Lisanga oyo ezali te, to ozali lisusu kati na yango te.',
    en: 'This group does not exist, or you are no longer in it.',
  ),
  // Préparer et démarrer
  'Il faut au moins 2 membres pour démarrer.': (
    fr: 'Il faut au moins 2 personnes pour commencer.',
    sw: 'Inahitajika angalau watu 2 kuanza.',
    ln: 'Esengeli ata bato 2 mpo na kobanda.',
    en: 'At least 2 people are needed to start.',
  ),
  'La date de début est passée : modifiez-la avant de démarrer.': (
    fr: 'La date du premier tour est passée. Choisissez une autre date.',
    sw: 'Tarehe ya zamu ya kwanza imepita. Chagua tarehe nyingine.',
    ln: 'Mokolo ya tango ya liboso eleki. Pona mokolo mosusu.',
    en: 'The first turn date has passed. Choose another date.',
  ),
  'Seul le président peut inviter de nouveaux membres.': (
    fr: 'Seul le président peut inviter.',
    sw: 'Ni rais tu anayeweza kualika.',
    ln: 'Kaka mokambi nde akoki kobenga bato.',
    en: 'Only the president can invite.',
  ),
  // Payer et confirmer
  'Ce tour est clos.': (
    fr: 'Ce tour est déjà fini.',
    sw: 'Zamu hii imeshaisha.',
    ln: 'Tango oyo esili kala.',
    en: 'This turn is already over.',
  ),
  'Vous avez déjà déclaré une cotisation pour ce tour.': (
    fr: 'Vous avez déjà dit « J\'ai payé » pour ce tour.',
    sw: 'Tayari umesema « Nimelipa » kwa zamu hii.',
    ln: 'Olobaki kala « Nafuti » mpo na tango oyo.',
    en: 'You already said “I paid” for this turn.',
  ),
  'Vous êtes le bénéficiaire de ce tour : vous ne cotisez pas pour vous-même.': (
    fr: 'C\'est vous qui recevez ce tour : vous ne payez pas.',
    sw: 'Ni wewe unayepokea zamu hii: hulipi.',
    ln: 'Ozali moto akozwa na tango oyo: ofutaka te.',
    en: 'You receive this turn: you do not pay.',
  ),
  'Pour un paiement en espèces, désignez un témoin du groupe.': (
    fr: 'Pour un paiement en main, choisissez une personne du groupe qui a vu.',
    sw: 'Kwa malipo ya mkononi, chagua mtu wa kikundi aliyeona.',
    ln: 'Mpo na lifuti na loboko, pona moto ya lisanga oyo amonaki.',
    en: 'For a cash payment, choose someone from the group who saw it.',
  ),
  'Cet ID de transaction a déjà été utilisé pour une autre cotisation.': (
    fr: 'Ce numéro de transaction a déjà servi. Vérifiez le SMS.',
    sw: 'Namba hii ya muamala imeshatumika. Kagua SMS.',
    ln: 'Nimero oyo ya transaction esalelamaki kala. Tala SMS.',
    en: 'This transaction number was already used. Check the SMS.',
  ),
  'Seul le bénéficiaire du tour confirme avoir reçu le paiement.': (
    fr: 'Seule la personne qui reçoit ce tour peut confirmer.',
    sw: 'Ni mtu anayepokea zamu hii tu anayeweza kuthibitisha.',
    ln: 'Kaka moto oyo azwi tango oyo nde akoki kondima.',
    en: 'Only the person receiving this turn can confirm.',
  ),
  'Vous avez déjà donné cette réponse.': (
    fr: 'C\'est déjà fait.',
    sw: 'Imeshafanyika.',
    ln: 'Esalemi kala.',
    en: 'Already done.',
  ),
  'Expliquez la contestation.': (
    fr: 'Dites en quelques mots quel est le problème.',
    sw: 'Eleza kwa maneno machache tatizo ni nini.',
    ln: 'Limbola na maloba moke mokakatano ezali nini.',
    en: 'Say in a few words what the problem is.',
  ),
  // Côté téléphone (ApiClient)
  'Pas de connexion. Vérifiez le réseau et réessayez.': (
    fr: 'Pas d\'internet. Vérifiez le réseau, puis réessayez.',
    sw: 'Hakuna intaneti. Kagua mtandao, kisha jaribu tena.',
    ln: 'Internet ezali te. Tala réseau, sima meka lisusu.',
    en: 'No internet. Check the network, then try again.',
  ),
  'Une erreur est survenue. Réessayez.': (
    fr: 'Ça n\'a pas marché. Réessayez.',
    sw: 'Haikufanikiwa. Jaribu tena.',
    ln: 'Esalemi te. Meka lisusu.',
    en: 'That did not work. Try again.',
  ),
};

/// Messages qui contiennent un nombre ou une date : motif → texte simple ({n} = premier groupe capturé).
final List<(RegExp, _Says)> _patterns = [
  (
    RegExp(r"^PIN incorrect\. Il vous reste (\d+) essai"),
    (
      fr: 'PIN faux. Encore {n} essai(s) possible(s).',
      sw: 'PIN si sahihi. Majaribio {n} yamebaki.',
      ln: 'PIN ezali mabe. Bomeki {n} etikali.',
      en: 'Wrong PIN. {n} tries left.',
    ),
  ),
  (
    // La date ISO du serveur ne dit rien à personne : on ne la montre pas
    RegExp(r"^PIN bloqué"),
    (
      fr: 'Trop de PIN faux. Attendez quelques minutes, puis réessayez.',
      sw: 'PIN zisizo sahihi ni nyingi. Subiri dakika chache, kisha jaribu tena.',
      ln: 'Ba PIN ya mabe mingi. Zela miniti moke, sima meka lisusu.',
      en: 'Too many wrong PINs. Wait a few minutes, then try again.',
    ),
  ),
];

/// Le message du serveur, dans la langue du membre et en mots simples (sinon tel quel).
String serverMessage(String message) {
  final lang = Lang.instance.current;
  String pick(_Says s) => switch (lang) {
    AppLanguage.fr => s.fr,
    AppLanguage.sw => s.sw,
    AppLanguage.ln => s.ln,
    AppLanguage.en => s.en,
  };
  final exact = _exact[message.trim()];
  if (exact != null) return pick(exact);
  for (final (pattern, says) in _patterns) {
    final m = pattern.firstMatch(message);
    if (m != null) return pick(says).replaceAll('{n}', m.groupCount > 0 ? (m[1] ?? '') : '');
  }
  return message;
}
