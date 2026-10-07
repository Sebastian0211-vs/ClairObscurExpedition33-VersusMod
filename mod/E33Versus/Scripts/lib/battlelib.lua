-- Start a battle through a constructed BP_GameAction_TriggerBattle (game-native caller; no struct params from Lua).
local function loadObj(path, cls)
  local o = StaticFindObject(path .. "." .. cls)
  if not o or not o:IsValid() then LoadAsset(path); o = StaticFindObject(path .. "." .. cls) end
  assert(o and o:IsValid(), "could not load " .. path)
  return o
end
function V.trigger()
  local dt = loadObj("/Game/jRPGTemplate/Datatables/DT_jRPG_Encounters", "DT_jRPG_Encounters")
  local cls = loadObj("/Game/Gameplay/GameActionsSystem/TriggerBattle/BP_GameAction_TriggerBattle", "BP_GameAction_TriggerBattle_C")
  loadObj("/Game/Gameplay/GameActionsSystem/TriggerBattle/BP_GameActionInstance_TriggerBattle", "BP_GameActionInstance_TriggerBattle_C")
  local ex = FindFirstOf("BP_GameActionExecutorComponent_C")
  assert(ex and ex:IsValid(), "no executor component")
  E33V_TRIGGER_SEQ = (E33V_TRIGGER_SEQ or 0) + 1
  local a = StaticConstructObject(cls, ex, FName("E33V_Trigger_" .. os.time() .. "_" .. E33V_TRIGGER_SEQ))
  local s = a["Battle Start Params"]
  local row = s.EncounterRow_25_76E166214BC95AA2A6A68DAD97A47C62
  row.DataTable = dt
  row.RowName = FName(E33V_ENC)
  s.EnemyGlobalID_12_57EC6FC84879C6C042EC7BB68F507FE2 = FName("E33Versus")
  s.EngagementType_15_D00812C641AFF3AF663DC6B910763D7D = 0
  local map = (V.battleMap and V.battleMap:IsValid()) and V.battleMap or V.pickBattleMap()
  s.BattleMapBP_18_E90DB870407FE894CA7200B075D98B4A = map
  s.TransitionType_31_74930912436832AA7F5A1C8F139A7E9A = 0
  s.PlayCameraIntro_21_FE94DAD74E9218AB0C1D48A3DC163272 = true
  s.ForceFleeImpossible_28_67F4412A4BF319F3EFFE8C8110E1CBC5 = false
  s.BackToExplorationOnLost_38_6E7B04094D32F81767771FA52BAE96D1 = true
  s.EncounterLevelOffset_53_1CBE091C40F1DC0A4C5A0EAC44E28B8E = E33V_LEVEL_OFFSET or 0
  s.AllowReserveTeam_67_D9994E8845C61EC655889197EAE92383 = false  -- reserve heroes would join when placeholders are kicked
  local r = s.BattleRewardParameters_76_45FD14DB462B63342F7B6189548E447A
  r.GoldMultiplier_20_465B27F2426EF03D5CDECAB763FE6B77 = 0.0
  r.ExperienceMultiplier_18_1E89E3064028B5F598B33C90855DC88D = 0.0
  r.OverrideLootItems_7_BF1C0C3F4AC3F143902F2CB6B39B58F1 = true
  r.ProgressEquippedLuminas_16_6057D8B44483C557F06B3DAD1EE61BE5 = false
  ex:ExecuteGameAction(a)
  V.log("battle triggered: " .. E33V_ENC .. " on " .. tostring(map and map:GetFName():ToString()))
end
