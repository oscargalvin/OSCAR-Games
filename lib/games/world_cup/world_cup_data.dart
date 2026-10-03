import 'world_cup_models.dart';
import 'world_cup_nations.dart';
import 'world_cup_ratings.dart';
import 'world_cup_rosters.dart';

export 'world_cup_nations.dart'
    show kWorldCupNations, kHandcraftedNationIds, kWorldCupQualifiedTeamCount, confederationForNation;
export 'world_cup_ratings.dart'
    show kWorldCupMaxPickRating, kPlayerRatingFloor, kPlayerRatingCeiling, kEnglandFixedRating, kJapanFixedRating, formatSeasonRating, effectiveRatingForStrength;

WorldCupNation nationById(String id) =>
    kWorldCupNations.firstWhere((n) => n.id == id, orElse: () => kWorldCupNations.first);

/// Banned from the entire game — never appears in any squad or lookup.
const Set<String> kBannedPlayerIds = {'bra_alisson'};
const Set<String> kBannedPlayerNames = {'Alisson'};

bool isBannedPlayer(WorldCupPlayer player) {
  final lower = player.name.toLowerCase();
  return kBannedPlayerIds.contains(player.id) ||
      kBannedPlayerNames.any((n) => lower.contains(n.toLowerCase()));
}

bool isBannedPlayerId(String id) => kBannedPlayerIds.contains(id);

List<WorldCupPlayer> withoutBannedPlayers(Iterable<WorldCupPlayer> players) =>
    players.where((p) => !isBannedPlayer(p)).toList();

/// Raw curated values — normalized to 1–99 (England → 1, Japan → 99) via [kWorldCupPlayerPool].
const List<WorldCupPlayer> _kWorldCupPlayerPoolRaw = [
  // Brazil
  WorldCupPlayer(id: 'bra_ederson', name: 'Ederson', nationId: 'bra', position: 'GK', rating2526: 89),
  WorldCupPlayer(id: 'bra_marquinhos', name: 'Marquinhos', nationId: 'bra', position: 'DEF', rating2526: 88),
  WorldCupPlayer(id: 'bra_militao', name: 'Militão', nationId: 'bra', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'bra_casemiro', name: 'Casemiro', nationId: 'bra', position: 'MID', rating2526: 85),
  WorldCupPlayer(id: 'bra_paqueta', name: 'Paquetá', nationId: 'bra', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'bra_raphinha', name: 'Raphinha', nationId: 'bra', position: 'FWD', rating2526: 87),
  WorldCupPlayer(id: 'bra_vinicius', name: 'Vinícius Jr', nationId: 'bra', position: 'FWD', rating2526: 92),
  WorldCupPlayer(id: 'bra_rodrygo', name: 'Rodrygo', nationId: 'bra', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'bra_endrick', name: 'Endrick', nationId: 'bra', position: 'FWD', rating2526: 81),
  WorldCupPlayer(id: 'bra_bruno_guimaraes', name: 'Bruno Guimarães', nationId: 'bra', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'bra_danilo', name: 'Danilo', nationId: 'bra', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'bra_bento', name: 'Bento', nationId: 'bra', position: 'GK', rating2526: 78),
  WorldCupPlayer(id: 'bra_youth', name: 'U21 Prospect', nationId: 'bra', position: 'MID', rating2526: 68.5),
  // Argentina
  WorldCupPlayer(id: 'arg_martinez', name: 'Emi Martínez', nationId: 'arg', position: 'GK', rating2526: 90),
  WorldCupPlayer(id: 'arg_otamendi', name: 'Otamendi', nationId: 'arg', position: 'DEF', rating2526: 84),
  WorldCupPlayer(id: 'arg_molina', name: 'Molina', nationId: 'arg', position: 'DEF', rating2526: 83),
  WorldCupPlayer(id: 'arg_enzo', name: 'Enzo Fernández', nationId: 'arg', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'arg_mac_allister', name: 'Mac Allister', nationId: 'arg', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'arg_dePaul', name: 'De Paul', nationId: 'arg', position: 'MID', rating2526: 85),
  WorldCupPlayer(id: 'arg_messi', name: 'Messi', nationId: 'arg', position: 'FWD', rating2526: 91),
  WorldCupPlayer(id: 'arg_lautaro', name: 'Lautaro', nationId: 'arg', position: 'FWD', rating2526: 88),
  WorldCupPlayer(id: 'arg_alvarez', name: 'Julián Álvarez', nationId: 'arg', position: 'FWD', rating2526: 87),
  WorldCupPlayer(id: 'arg_romero', name: 'Romero', nationId: 'arg', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'arg_paredes', name: 'Paredes', nationId: 'arg', position: 'MID', rating2526: 82),
  WorldCupPlayer(id: 'arg_rulli', name: 'Rulli', nationId: 'arg', position: 'GK', rating2526: 79),
  WorldCupPlayer(id: 'arg_reserve', name: 'Reserve CM', nationId: 'arg', position: 'MID', rating2526: 72.3),
  // France
  WorldCupPlayer(id: 'fra_maignan', name: 'Maignan', nationId: 'fra', position: 'GK', rating2526: 89),
  WorldCupPlayer(id: 'fra_saliba', name: 'Saliba', nationId: 'fra', position: 'DEF', rating2526: 90),
  WorldCupPlayer(id: 'fra_kounde', name: 'Koundé', nationId: 'fra', position: 'DEF', rating2526: 87),
  WorldCupPlayer(id: 'fra_tchouameni', name: 'Tchouaméni', nationId: 'fra', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'fra_camavinga', name: 'Camavinga', nationId: 'fra', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'fra_griezmann', name: 'Griezmann', nationId: 'fra', position: 'FWD', rating2526: 88),
  WorldCupPlayer(id: 'fra_mbappe', name: 'Mbappé', nationId: 'fra', position: 'FWD', rating2526: 93),
  WorldCupPlayer(id: 'fra_dembele', name: 'Dembélé', nationId: 'fra', position: 'FWD', rating2526: 88),
  WorldCupPlayer(id: 'fra_kolo_muani', name: 'Kolo Muani', nationId: 'fra', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'fra_upamecano', name: 'Upamecano', nationId: 'fra', position: 'DEF', rating2526: 85),
  WorldCupPlayer(id: 'fra_zaire', name: 'Zaïre-Emery', nationId: 'fra', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'fra_areola', name: 'Areola', nationId: 'fra', position: 'GK', rating2526: 77),
  WorldCupPlayer(id: 'fra_youth', name: 'Academy Winger', nationId: 'fra', position: 'FWD', rating2526: 70.8),
  // England
  WorldCupPlayer(id: 'eng_pickford', name: 'Pickford', nationId: 'eng', position: 'GK', rating2526: 86),
  WorldCupPlayer(id: 'eng_stones', name: 'Stones', nationId: 'eng', position: 'DEF', rating2526: 87),
  WorldCupPlayer(id: 'eng_maguire', name: 'Maguire', nationId: 'eng', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'eng_rice', name: 'Declan Rice', nationId: 'eng', position: 'MID', rating2526: 89),
  WorldCupPlayer(id: 'eng_bellingham', name: 'Bellingham', nationId: 'eng', position: 'MID', rating2526: 91),
  WorldCupPlayer(id: 'eng_foden', name: 'Foden', nationId: 'eng', position: 'MID', rating2526: 88),
  WorldCupPlayer(id: 'eng_saka', name: 'Saka', nationId: 'eng', position: 'FWD', rating2526: 89),
  WorldCupPlayer(id: 'eng_kane', name: 'Kane', nationId: 'eng', position: 'FWD', rating2526: 90),
  WorldCupPlayer(id: 'eng_watkins', name: 'Watkins', nationId: 'eng', position: 'FWD', rating2526: 85),
  WorldCupPlayer(id: 'eng_walker', name: 'Walker', nationId: 'eng', position: 'DEF', rating2526: 84),
  WorldCupPlayer(id: 'eng_mainoo', name: 'Mainoo', nationId: 'eng', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'eng_ramsdale', name: 'Ramsdale', nationId: 'eng', position: 'GK', rating2526: 78),
  WorldCupPlayer(id: 'eng_youth', name: 'U21 Full-back', nationId: 'eng', position: 'DEF', rating2526: 69.2),
  // Germany
  WorldCupPlayer(id: 'ger_neuer', name: 'Neuer', nationId: 'ger', position: 'GK', rating2526: 87),
  WorldCupPlayer(id: 'ger_rudiger', name: 'Rüdiger', nationId: 'ger', position: 'DEF', rating2526: 88),
  WorldCupPlayer(id: 'ger_tah', name: 'Tah', nationId: 'ger', position: 'DEF', rating2526: 85),
  WorldCupPlayer(id: 'ger_kimmich', name: 'Kimmich', nationId: 'ger', position: 'MID', rating2526: 89),
  WorldCupPlayer(id: 'ger_gundogan', name: 'Gündogan', nationId: 'ger', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'ger_musiala', name: 'Musiala', nationId: 'ger', position: 'MID', rating2526: 90),
  WorldCupPlayer(id: 'ger_wirtz', name: 'Wirtz', nationId: 'ger', position: 'MID', rating2526: 89),
  WorldCupPlayer(id: 'ger_havertz', name: 'Havertz', nationId: 'ger', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'ger_fulkrug', name: 'Füllkrug', nationId: 'ger', position: 'FWD', rating2526: 83),
  WorldCupPlayer(id: 'ger_sane', name: 'Sané', nationId: 'ger', position: 'FWD', rating2526: 85),
  WorldCupPlayer(id: 'ger_mittelstadt', name: 'Mittelstädt', nationId: 'ger', position: 'DEF', rating2526: 81),
  WorldCupPlayer(id: 'ger_baumann', name: 'Baumann', nationId: 'ger', position: 'GK', rating2526: 79),
  WorldCupPlayer(id: 'ger_youth', name: 'Reserve Striker', nationId: 'ger', position: 'FWD', rating2526: 71.5),
  // Spain
  WorldCupPlayer(id: 'esp_simon', name: 'Unai Simón', nationId: 'esp', position: 'GK', rating2526: 87),
  WorldCupPlayer(id: 'esp_laporte', name: 'Laporte', nationId: 'esp', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'esp_carvajal', name: 'Carvajal', nationId: 'esp', position: 'DEF', rating2526: 85),
  WorldCupPlayer(id: 'esp_rodri', name: 'Rodri', nationId: 'esp', position: 'MID', rating2526: 91),
  WorldCupPlayer(id: 'esp_pedri', name: 'Pedri', nationId: 'esp', position: 'MID', rating2526: 89),
  WorldCupPlayer(id: 'esp_gavi', name: 'Gavi', nationId: 'esp', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'esp_yamal', name: 'Lamine Yamal', nationId: 'esp', position: 'FWD', rating2526: 90),
  WorldCupPlayer(id: 'esp_morata', name: 'Morata', nationId: 'esp', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'esp_nico_williams', name: 'Nico Williams', nationId: 'esp', position: 'FWD', rating2526: 88),
  WorldCupPlayer(id: 'esp_olmo', name: 'Olmo', nationId: 'esp', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'esp_le_normand', name: 'Le Normand', nationId: 'esp', position: 'DEF', rating2526: 84),
  WorldCupPlayer(id: 'esp_raya', name: 'Raya', nationId: 'esp', position: 'GK', rating2526: 85),
  WorldCupPlayer(id: 'esp_youth', name: 'B-team CB', nationId: 'esp', position: 'DEF', rating2526: 73.8),
  // Portugal
  WorldCupPlayer(id: 'por_dio', name: 'Diogo Costa', nationId: 'por', position: 'GK', rating2526: 86),
  WorldCupPlayer(id: 'por_dias', name: 'Rúben Dias', nationId: 'por', position: 'DEF', rating2526: 88),
  WorldCupPlayer(id: 'por_cancelo', name: 'Cancelo', nationId: 'por', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'por_bruno', name: 'Bruno Fernandes', nationId: 'por', position: 'MID', rating2526: 88),
  WorldCupPlayer(id: 'por_vitinha', name: 'Vitinha', nationId: 'por', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'por_ronaldo', name: 'Ronaldo', nationId: 'por', position: 'FWD', rating2526: 87),
  WorldCupPlayer(id: 'por_leao', name: 'Leão', nationId: 'por', position: 'FWD', rating2526: 88),
  WorldCupPlayer(id: 'por_ramos', name: 'Gonçalo Ramos', nationId: 'por', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'por_neves', name: 'Rúben Neves', nationId: 'por', position: 'MID', rating2526: 85),
  WorldCupPlayer(id: 'por_mendes', name: 'Nuno Mendes', nationId: 'por', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'por_jota', name: 'Jota', nationId: 'por', position: 'FWD', rating2526: 85),
  WorldCupPlayer(id: 'por_patricio', name: 'Patrício', nationId: 'por', position: 'GK', rating2526: 78),
  WorldCupPlayer(id: 'por_youth', name: 'Youth AM', nationId: 'por', position: 'MID', rating2526: 74.2),
  // Netherlands
  WorldCupPlayer(id: 'ned_verbruggen', name: 'Verbruggen', nationId: 'ned', position: 'GK', rating2526: 84),
  WorldCupPlayer(id: 'ned_van_dijk', name: 'Van Dijk', nationId: 'ned', position: 'DEF', rating2526: 89),
  WorldCupPlayer(id: 'ned_ake', name: 'Aké', nationId: 'ned', position: 'DEF', rating2526: 85),
  WorldCupPlayer(id: 'ned_de_jong', name: 'F. de Jong', nationId: 'ned', position: 'MID', rating2526: 87),
  WorldCupPlayer(id: 'ned_reijnders', name: 'Reijnders', nationId: 'ned', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'ned_gakpo', name: 'Gakpo', nationId: 'ned', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'ned_deppay', name: 'Depay', nationId: 'ned', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'ned_simons', name: 'Simons', nationId: 'ned', position: 'MID', rating2526: 85),
  WorldCupPlayer(id: 'ned_dumfries', name: 'Dumfries', nationId: 'ned', position: 'DEF', rating2526: 84),
  WorldCupPlayer(id: 'ned_frimpong', name: 'Frimpong', nationId: 'ned', position: 'DEF', rating2526: 86),
  WorldCupPlayer(id: 'ned_weghorst', name: 'Weghorst', nationId: 'ned', position: 'FWD', rating2526: 81),
  WorldCupPlayer(id: 'ned_flekken', name: 'Flekken', nationId: 'ned', position: 'GK', rating2526: 79),
  WorldCupPlayer(id: 'ned_youth', name: 'U21 Winger', nationId: 'ned', position: 'FWD', rating2526: 72.0),
  // USA
  WorldCupPlayer(id: 'usa_turner', name: 'Turner', nationId: 'usa', position: 'GK', rating2526: 82),
  WorldCupPlayer(id: 'usa_ream', name: 'Ream', nationId: 'usa', position: 'DEF', rating2526: 78),
  WorldCupPlayer(id: 'usa_robinson', name: 'Antonee Robinson', nationId: 'usa', position: 'DEF', rating2526: 81),
  WorldCupPlayer(id: 'usa_adams', name: 'Tyler Adams', nationId: 'usa', position: 'MID', rating2526: 82),
  WorldCupPlayer(id: 'usa_mckennie', name: 'McKennie', nationId: 'usa', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'usa_pulisic', name: 'Pulisic', nationId: 'usa', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'usa_weah', name: 'Weah', nationId: 'usa', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'usa_pep', name: 'Pepi', nationId: 'usa', position: 'FWD', rating2526: 80),
  WorldCupPlayer(id: 'usa_musah', name: 'Musah', nationId: 'usa', position: 'MID', rating2526: 81),
  WorldCupPlayer(id: 'usa_dest', name: 'Dest', nationId: 'usa', position: 'DEF', rating2526: 79),
  WorldCupPlayer(id: 'usa_balogun', name: 'Balogun', nationId: 'usa', position: 'FWD', rating2526: 81),
  WorldCupPlayer(id: 'usa_horvath', name: 'Horvath', nationId: 'usa', position: 'GK', rating2526: 76),
  WorldCupPlayer(id: 'usa_youth', name: 'MLS Prospect', nationId: 'usa', position: 'MID', rating2526: 65.4),
  // Mexico
  WorldCupPlayer(id: 'mex_ocha', name: 'Ochoa', nationId: 'mex', position: 'GK', rating2526: 81),
  WorldCupPlayer(id: 'mex_vasquez', name: 'Vázquez', nationId: 'mex', position: 'DEF', rating2526: 80),
  WorldCupPlayer(id: 'mex_montes', name: 'Montes', nationId: 'mex', position: 'DEF', rating2526: 79),
  WorldCupPlayer(id: 'mex_alvarez_ed', name: 'Edson Álvarez', nationId: 'mex', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'mex_chavez', name: 'Chávez', nationId: 'mex', position: 'MID', rating2526: 80),
  WorldCupPlayer(id: 'mex_lozano', name: 'Lozano', nationId: 'mex', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'mex_jimenez', name: 'Jiménez', nationId: 'mex', position: 'FWD', rating2526: 81),
  WorldCupPlayer(id: 'mex_vega', name: 'Alexis Vega', nationId: 'mex', position: 'FWD', rating2526: 79),
  WorldCupPlayer(id: 'mex_gallardo', name: 'Gallardo', nationId: 'mex', position: 'DEF', rating2526: 78),
  WorldCupPlayer(id: 'mex_pineda', name: 'Orbelín Pineda', nationId: 'mex', position: 'MID', rating2526: 80),
  WorldCupPlayer(id: 'mex_sanchez', name: 'Sánchez', nationId: 'mex', position: 'GK', rating2526: 77),
  WorldCupPlayer(id: 'mex_antuna', name: 'Antuna', nationId: 'mex', position: 'FWD', rating2526: 78),
  WorldCupPlayer(id: 'mex_youth', name: 'Liga MX Youth', nationId: 'mex', position: 'DEF', rating2526: 64.8),
  // Japan
  WorldCupPlayer(id: 'jpn_gonda', name: 'Gonda', nationId: 'jpn', position: 'GK', rating2526: 78),
  WorldCupPlayer(id: 'jpn_tomiyasu', name: 'Tomiyasu', nationId: 'jpn', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'jpn_itakura', name: 'Itakura', nationId: 'jpn', position: 'DEF', rating2526: 81),
  WorldCupPlayer(id: 'jpn_endo', name: 'Wataru Endō', nationId: 'jpn', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'jpn_kubo', name: 'Takefusa Kubo', nationId: 'jpn', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'jpn_mitoma', name: 'Mitoma', nationId: 'jpn', position: 'FWD', rating2526: 85),
  WorldCupPlayer(id: 'jpn_minamino', name: 'Minamino', nationId: 'jpn', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'jpn_kamada', name: 'Kamada', nationId: 'jpn', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'jpn_tanaka', name: 'Kaoru Tanaka', nationId: 'jpn', position: 'MID', rating2526: 80),
  WorldCupPlayer(id: 'jpn_sakai', name: 'Sakai', nationId: 'jpn', position: 'DEF', rating2526: 79),
  WorldCupPlayer(id: 'jpn_daizen', name: 'Maeda', nationId: 'jpn', position: 'FWD', rating2526: 80),
  WorldCupPlayer(id: 'jpn_suzuki', name: 'Suzuki', nationId: 'jpn', position: 'GK', rating2526: 81),
  WorldCupPlayer(id: 'jpn_youth', name: 'J-League Prospect', nationId: 'jpn', position: 'MID', rating2526: 66.7),
  // Colombia
  WorldCupPlayer(id: 'col_ospin', name: 'Ospina', nationId: 'col', position: 'GK', rating2526: 80),
  WorldCupPlayer(id: 'col_sanchez_d', name: 'D. Sánchez', nationId: 'col', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'col_mosquera', name: 'Mosquera', nationId: 'col', position: 'DEF', rating2526: 80),
  WorldCupPlayer(id: 'col_barrios', name: 'Barrios', nationId: 'col', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'col_james', name: 'James Rodríguez', nationId: 'col', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'col_diaz', name: 'Luis Díaz', nationId: 'col', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'col_borre', name: 'Borré', nationId: 'col', position: 'FWD', rating2526: 81),
  WorldCupPlayer(id: 'col_sinisterra', name: 'Sinisterra', nationId: 'col', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'col_carrascal', name: 'Carrascal', nationId: 'col', position: 'MID', rating2526: 82),
  WorldCupPlayer(id: 'col_lerma', name: 'Lerma', nationId: 'col', position: 'MID', rating2526: 81),
  WorldCupPlayer(id: 'col_teglia', name: 'Teglia', nationId: 'col', position: 'DEF', rating2526: 78),
  WorldCupPlayer(id: 'col_montero', name: 'Montero', nationId: 'col', position: 'GK', rating2526: 76),
  WorldCupPlayer(id: 'col_youth', name: 'Reserve FW', nationId: 'col', position: 'FWD', rating2526: 67.3),
  // Belgium
  WorldCupPlayer(id: 'bel_courtois', name: 'Courtois', nationId: 'bel', position: 'GK', rating2526: 90),
  WorldCupPlayer(id: 'bel_theate', name: 'Theate', nationId: 'bel', position: 'DEF', rating2526: 85),
  WorldCupPlayer(id: 'bel_fa', name: 'Faes', nationId: 'bel', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'bel_debruyne', name: 'De Bruyne', nationId: 'bel', position: 'MID', rating2526: 90),
  WorldCupPlayer(id: 'bel_tielemans', name: 'Tielemans', nationId: 'bel', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'bel_lukaku', name: 'Lukaku', nationId: 'bel', position: 'FWD', rating2526: 85),
  WorldCupPlayer(id: 'bel_doku', name: 'Doku', nationId: 'bel', position: 'FWD', rating2526: 86),
  WorldCupPlayer(id: 'bel_trossard', name: 'Trossard', nationId: 'bel', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'bel_onana', name: 'Amadou Onana', nationId: 'bel', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'bel_castagne', name: 'Castagne', nationId: 'bel', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'bel_carrasco', name: 'Carrasco', nationId: 'bel', position: 'FWD', rating2526: 83),
  WorldCupPlayer(id: 'bel_sels', name: 'Sels', nationId: 'bel', position: 'GK', rating2526: 78),
  WorldCupPlayer(id: 'bel_youth', name: 'U21 CB', nationId: 'bel', position: 'DEF', rating2526: 70.5),
  // Croatia
  WorldCupPlayer(id: 'cro_livakovic', name: 'Livaković', nationId: 'cro', position: 'GK', rating2526: 84),
  WorldCupPlayer(id: 'cro_gvardiol', name: 'Gvardiol', nationId: 'cro', position: 'DEF', rating2526: 87),
  WorldCupPlayer(id: 'cro_sutalo', name: 'Šutalo', nationId: 'cro', position: 'DEF', rating2526: 81),
  WorldCupPlayer(id: 'cro_modric', name: 'Modrić', nationId: 'cro', position: 'MID', rating2526: 86),
  WorldCupPlayer(id: 'cro_kovacic', name: 'Kovačić', nationId: 'cro', position: 'MID', rating2526: 85),
  WorldCupPlayer(id: 'cro_brozo', name: 'Brozović', nationId: 'cro', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'cro_perisic', name: 'Perišić', nationId: 'cro', position: 'FWD', rating2526: 83),
  WorldCupPlayer(id: 'cro_kramaric', name: 'Kramarić', nationId: 'cro', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'cro_pasalic', name: 'Pašalić', nationId: 'cro', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'cro_stanisic', name: 'Stanišić', nationId: 'cro', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'cro_majer', name: 'Majer', nationId: 'cro', position: 'MID', rating2526: 82),
  WorldCupPlayer(id: 'cro_grbic', name: 'Grbić', nationId: 'cro', position: 'GK', rating2526: 77),
  WorldCupPlayer(id: 'cro_youth', name: 'Reserve MF', nationId: 'cro', position: 'MID', rating2526: 69.8),
  // Morocco
  WorldCupPlayer(id: 'mar_bono', name: 'Bono', nationId: 'mar', position: 'GK', rating2526: 86),
  WorldCupPlayer(id: 'mar_hakimi', name: 'Hakimi', nationId: 'mar', position: 'DEF', rating2526: 87),
  WorldCupPlayer(id: 'mar_saiss', name: 'Saïss', nationId: 'mar', position: 'DEF', rating2526: 82),
  WorldCupPlayer(id: 'mar_amrabat', name: 'Amrabat', nationId: 'mar', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'mar_ziyech', name: 'Ziyech', nationId: 'mar', position: 'MID', rating2526: 83),
  WorldCupPlayer(id: 'mar_en_nesyri', name: 'En-Nesyri', nationId: 'mar', position: 'FWD', rating2526: 84),
  WorldCupPlayer(id: 'mar_boufal', name: 'Boufal', nationId: 'mar', position: 'FWD', rating2526: 82),
  WorldCupPlayer(id: 'mar_tissoudali', name: 'Tissoudali', nationId: 'mar', position: 'FWD', rating2526: 80),
  WorldCupPlayer(id: 'mar_ounahi', name: 'Ounahi', nationId: 'mar', position: 'MID', rating2526: 84),
  WorldCupPlayer(id: 'mar_aguerd', name: 'Aguerd', nationId: 'mar', position: 'DEF', rating2526: 83),
  WorldCupPlayer(id: 'mar_el_kaabi', name: 'El Kaabi', nationId: 'mar', position: 'FWD', rating2526: 79),
  WorldCupPlayer(id: 'mar_munir', name: 'Munir', nationId: 'mar', position: 'GK', rating2526: 77),
  WorldCupPlayer(id: 'mar_youth', name: 'Botola Youth', nationId: 'mar', position: 'DEF', rating2526: 63.5),
];

List<WorldCupPlayer> get kWorldCupPlayerPool =>
    withoutBannedPlayers(_kWorldCupPlayerPoolRaw.map(normalizePlayerRating));

final Map<String, WorldCupPlayer> _allPlayersById = {};
bool _allPlayersCacheBuilt = false;

void _ensureAllPlayersCache() {
  if (_allPlayersCacheBuilt) return;
  for (final nation in kWorldCupNations) {
    for (final p in playersForNation(nation.id)) {
      if (!isBannedPlayer(p)) {
        _allPlayersById[p.id] = p;
      }
    }
  }
  _allPlayersCacheBuilt = true;
}

List<WorldCupPlayer> playersForNation(String nationId) {
  final generated = withoutBannedPlayers(_generatedPlayersForNation(nationId));
  final handcrafted =
      withoutBannedPlayers(kWorldCupPlayerPool.where((p) => p.nationId == nationId)).toList()
        ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
  if (handcrafted.isEmpty) return generated;

  final merged = <WorldCupPlayer>[...handcrafted];
  for (final filler in generated) {
    if (merged.length >= kWorldCupSquadSize) break;
    if (merged.any((p) => p.id == filler.id)) continue;
    merged.add(filler);
  }
  merged.sort((a, b) => b.rating2526.compareTo(a.rating2526));
  return withoutBannedPlayers(merged.take(kWorldCupSquadSize));
}

/// 11 starters + 7 on the bench.
const _genPositions = [
  'GK', 'DEF', 'DEF', 'DEF', 'DEF', 'MID', 'MID', 'MID', 'FWD', 'FWD', 'FWD',
  'GK', 'DEF', 'MID', 'MID', 'FWD', 'FWD', 'MID',
];
const _genRoleNames = {
  'GK': ['First-choice GK', 'Backup keeper'],
  'DEF': ['Centre back', 'Full back', 'Stopper', 'Cover defender'],
  'MID': ['Playmaker', 'Box-to-box', 'Wide midfielder', 'Deep-lying 6'],
  'FWD': ['Striker', 'Winger', 'Second striker', 'Target forward'],
};

List<WorldCupPlayer> _generatedPlayersForNation(String nationId) {
  final nation = nationById(nationId);
  final base = kNationSquadBaseRating[nationId] ?? 70.0;
  final seed = nationId.codeUnits.fold<int>(0, (a, c) => a + c);
  final players = <WorldCupPlayer>[];
  for (var i = 0; i < kWorldCupSquadSize; i++) {
    final pos = _genPositions[i];
    final roleNames = _genRoleNames[pos]!;
    final names = kRealSquadNames[nationId];
    var name = names != null && names.length > i
        ? names[i]
        : roleNames[(seed + i) % roleNames.length];
    if (name.toLowerCase().contains('alisson')) {
      name = '${roleNames[(seed + i + 2) % roleNames.length]} (${nation.name})';
    }
    final rating = seasonRatingForGeneratedNation(
      nationId,
      base,
      seed + i,
      i < kWorldCupStartingXi,
    );
    players.add(WorldCupPlayer(
      id: '${nationId}_gen_$i',
      name: names != null ? name : '$name (${nation.name})',
      nationId: nationId,
      position: pos,
      rating2526: rating.toDouble(),
    ));
  }
  return players;
}

WorldCupPlayer playerById(String id) {
  if (id.isEmpty) {
    return WorldCupPlayer(
      id: 'unknown',
      name: 'Unknown',
      nationId: 'unk',
      position: 'MID',
      rating2526: kPlayerRatingFloor.toDouble(),
    );
  }

  if (isBannedPlayerId(id)) {
    final nationId = id.split('_').first;
    final pool = playersForNation(nationId);
    if (pool.isNotEmpty) return pool.first;
    return WorldCupPlayer(
      id: 'unknown',
      name: 'Unknown',
      nationId: nationId,
      position: 'MID',
      rating2526: kPlayerRatingFloor.toDouble(),
    );
  }

  _ensureAllPlayersCache();
  final cached = _allPlayersById[id];
  if (cached != null) {
    if (isBannedPlayer(cached)) {
      final pool = playersForNation(cached.nationId);
      return pool.isNotEmpty ? pool.first : cached;
    }
    return cached;
  }

  final nationId = id.split('_').first;
  if (nationId.length == 3 && kWorldCupNations.any((n) => n.id == nationId)) {
    for (final p in playersForNation(nationId)) {
      if (p.id == id) {
        _allPlayersById[id] = p;
        return p;
      }
    }
  }

  for (final p in kWorldCupPlayerPool) {
    if (p.id == id) {
      _allPlayersById[id] = p;
      return p;
    }
  }

  return WorldCupPlayer(
    id: id,
    name: 'Unknown player',
    nationId: nationId.length == 3 ? nationId : 'unk',
    position: 'MID',
    rating2526: kPlayerRatingFloor.toDouble(),
  );
}

/// Squad list for UI — always uses the correct national roster (never a wrong fallback).
List<WorldCupPlayer> squadPlayers(WorldCupSquad squad) {
  final canonById = {for (final p in playersForNation(squad.nationId)) p.id: p};
  final seen = <String>{};
  final out = <WorldCupPlayer>[];

  void add(WorldCupPlayer p) {
    if (isBannedPlayer(p)) return;
    if (seen.contains(p.id) || out.length >= kWorldCupSquadSize) return;
    seen.add(p.id);
    out.add(p);
  }

  for (final id in squad.playerIds) {
    if (isBannedPlayerId(id)) continue;
    final own = canonById[id];
    if (own != null) {
      add(own);
      continue;
    }
    if (!id.startsWith('${squad.nationId}_')) {
      _ensureAllPlayersCache();
      final foreign = _allPlayersById[id];
      if (foreign != null && foreign.nationId != squad.nationId) {
        add(foreign);
      }
    }
  }

  for (final p in playersForNation(squad.nationId)) {
    if (out.length >= kWorldCupSquadSize) break;
    add(p);
  }

  return out;
}

WorldCupPlayer playerFromSquad(WorldCupSquad squad, String playerId) {
  for (final p in squadPlayers(squad)) {
    if (p.id == playerId) return p;
  }
  return playerById(playerId);
}

bool squadLooksCorrupt(WorldCupSquad squad) {
  if (squad.playerIds.isEmpty) return true;
  if (squad.playerIds.any(isBannedPlayerId)) return true;
  if (squad.playerIds.toSet().length == 1 && squad.playerIds.length > 1) return true;
  final ownCount =
      squad.playerIds.where((id) => id.startsWith('${squad.nationId}_')).length;
  return ownCount < kWorldCupStartingXi;
}

/// Full squad: 18 players (11 starting XI + 7 bench).
WorldCupSquad initialSquadForNation(String nationId) {
  final pool = List<WorldCupPlayer>.from(playersForNation(nationId))
    ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
  final ids = pool.map((p) => p.id).take(kWorldCupSquadSize).toList();
  final xi = ids.take(kWorldCupStartingXi).toList();
  return WorldCupSquad(
    nationId: nationId,
    playerIds: ids,
    startingXiIds: xi,
  );
}

double squadFieldStrength(WorldCupSquad squad) {
  final xi = squad.startingXiIds
      .map(playerById)
      .take(kWorldCupStartingXi)
      .toList();
  if (xi.isEmpty) return kPlayerRatingFloor.toDouble();
  return xi.map((p) => effectiveRatingForStrength(p.rating2526)).reduce((a, b) => a + b) /
      xi.length;
}

double nationFieldStrength(String nationId, {Set<String>? excludeIds}) {
  final ex = excludeIds ?? {};
  final pool = playersForNation(nationId).where((p) => !ex.contains(p.id)).toList()
    ..sort((a, b) => b.rating2526.compareTo(a.rating2526));
  final xi = pool.take(kWorldCupStartingXi);
  if (xi.isEmpty) return kPlayerRatingFloor.toDouble();
  return xi.map((p) => effectiveRatingForStrength(p.rating2526)).reduce((a, b) => a + b) /
      xi.length;
}
