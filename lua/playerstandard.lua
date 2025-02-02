-- Friendly Fire
local original_init = PlayerStandard.init
function PlayerStandard:init(unit)
    original_init(self, unit)

    if Global.game_settings and Global.game_settings.one_down then
        self._slotmask_bullet_impact_targets = self._slotmask_bullet_impact_targets + 3
    else
        self._slotmask_bullet_impact_targets = managers.mutators:modify_value("PlayerStandard:init:melee_slot_mask", self._slotmask_bullet_impact_targets)
    end
end

-- separate lock n' load from ovka
function PlayerStandard:_get_swap_speed_multiplier()
	local multiplier = 1
	local weapon_tweak_data = self._equipped_unit:base():weapon_tweak_data()
	multiplier = multiplier * managers.player:upgrade_value("weapon", "swap_speed_multiplier", 1)
	multiplier = multiplier * managers.player:upgrade_value("weapon", "passive_swap_speed_multiplier", 1)
	multiplier = multiplier * managers.player:upgrade_value("weapon", "generic_swap_speed_multiplier", 1)

	for _, category in ipairs(weapon_tweak_data.categories) do
		multiplier = multiplier * managers.player:upgrade_value(category, "swap_speed_multiplier", 1)
	end

	multiplier = multiplier * managers.player:upgrade_value("team", "crew_faster_swap", 1)

	if managers.player:has_activate_temporary_upgrade("temporary", "swap_weapon_faster") then
		multiplier = multiplier * managers.player:temporary_upgrade_value("temporary", "swap_weapon_faster", 1)
	end

	multiplier = managers.modifiers:modify_value("PlayerStandard:GetSwapSpeedMultiplier", multiplier)

	return multiplier
end

-- No more sixth sense
Hooks:OverrideFunction(PlayerStandard, "_update_omniscience",
function(self, ...)
    return
end)

-- Don't update sixth sense anymore
Hooks:OverrideFunction(PlayerStandard, "update",
function(self, t, dt)
    PlayerMovementState.update(self, t, dt)
    self:_calculate_standard_variables(t, dt)
    self:_update_ground_ray()
    self:_update_fwd_ray()
    self:_update_check_actions(t, dt)

    if self._menu_closed_fire_cooldown > 0 then
        self._menu_closed_fire_cooldown = self._menu_closed_fire_cooldown - dt
    end

    self:_update_movement(t, dt)
    self:_upd_nav_data()
    managers.hud:_update_crosshair_offset(t, dt)
    self:_upd_stance_switch_delay(t, dt)
end)

-- Melee while running
-- Code from melee overhaul
Hooks:PostHook(PlayerStandard, "_start_action_running", "eclipse_start_action_running", function(self, t)
	if managers.player and managers.player:has_category_upgrade("player", "run_and_melee_eclipse") then
		if not self._move_dir then
			self._running_wanted = true
			return
		end

		if self:on_ladder() or self:_on_zipline() then
			return
		end

		if self._shooting and not managers.player.RUN_AND_SHOOT or self:_changing_weapon() or self._use_item_expire_t or self._state_data.in_air or self:_is_throwing_projectile() or self:_is_charging_weapon() then
			self._running_wanted = true
			return
		end

		if self._state_data.ducking and not self:_can_stand() then
			self._running_wanted = true
			return
		end

		if not self:_can_run_directional() then
			return
		end

		if not self:_is_meleeing() and self._camera_unit:base()._melee_item_units then
			self._running_wanted = true
			return
		end

		self._running_wanted = false

		if managers.player:get_player_rule("no_run") then
			return
		end

		if not self._unit:movement():is_above_stamina_threshold() then
			return
		end

		if (not self._state_data.shake_player_start_running or not self._ext_camera:shaker():is_playing(self._state_data.shake_player_start_running)) and managers.user:get_setting("use_headbob") then
			self._state_data.shake_player_start_running = self._ext_camera:play_shaker("player_start_running", 0.75)
		end

		self:set_running(true)

		self._end_running_expire_t = nil
		self._start_running_t = t

		if not self.RUN_AND_RELOAD then
			self:_interupt_action_reload(t)
		end

		self:_interupt_action_steelsight(t)
		self:_interupt_action_ducking(t)
	end
end)

function PlayerStandard:_end_action_running(t)
	if not self._end_running_expire_t then
		local speed_multiplier = self._equipped_unit:base():exit_run_speed_multiplier()
		self._end_running_expire_t = t + 0.4 / speed_multiplier
		local stop_running = not self._equipped_unit:base():run_and_shoot_allowed() and (not self.RUN_AND_RELOAD or not self:_is_reloading())

		if not self:_is_meleeing() and stop_running then
			self._ext_camera:play_redirect(self:get_animation("stop_running"), speed_multiplier)
		end
	end
end

Hooks:PreHook(PlayerStandard, "_start_action_melee", "eclipse_pre_start_action_melee", function(self, t, input, instant)
	self._state_data.melee_running_wanted = true and self._running and not self._end_running_expire_t
end)

Hooks:PostHook(PlayerStandard, "_start_action_melee", "eclipse_post_start_action_melee", function(self, t, input, instant)
	if self._state_data.melee_running_wanted then
		self._running_wanted = true
	end

	self._state_data.melee_running_wanted = nil
end)

Hooks:PreHook(PlayerStandard, "_update_melee_timers", "eclipse_update_melee_timers", function(self, t, input)
	local melee_entry = managers.blackmarket:equipped_melee_weapon()
	local instant = tweak_data.blackmarket.melee_weapons[melee_entry].instant

	if not instant and not self._state_data.melee_repeat_expire_t and self._state_data.melee_expire_t and t >= self._state_data.melee_expire_t then
		if self._running and not self._end_running_expire_t then
			if not self:_is_reloading() or not self.RUN_AND_RELOAD then
				if not self._equipped_unit:base():run_and_shoot_allowed() and not self._state_data.meleeing then
					self._ext_camera:play_redirect(self:get_animation("start_running"))
				else
					if not self._state_data.meleeing then
						self._ext_camera:play_redirect(self:get_animation("idle"))
					end
				end
			end
		end
	end

	if instant and self._state_data.melee_expire_t and t >= self._state_data.melee_expire_t then
		if self._running and not self._end_running_expire_t then
			if not self:_is_reloading() or not self.RUN_AND_RELOAD then
				if not self._equipped_unit:base():run_and_shoot_allowed() and not self._state_data.meleeing then
					self._ext_camera:play_redirect(self:get_animation("start_running"))
				else
					if not self._state_data.meleeing then
						self._ext_camera:play_redirect(self:get_animation("idle"))
					end
				end
			end
		end
	end
end)

Hooks:PostHook(PlayerStandard, "_interupt_action_melee", "eclipse_interupt_action_melee", function(self, t)
	if managers.player and managers.player:has_category_upgrade("player", "run_and_melee_eclipse") then
		local running = self._running and not self._end_running_expire_t

		self:_interupt_action_running(t)

		if running then
			self._running_wanted = true
		end
	end
end)
-- End melee overhaul code

-- no interaction cooldown, credit goes to chibibowa
local old_check_use = PlayerStandard._check_use_item

function PlayerStandard:_check_use_item(t, input)
	if input.btn_use_item_release and self._throw_time and t and t < self._throw_time then
		managers.player:drop_carry()
		self._throw_time = nil
		return true
	else return old_check_use(self, t, input)
	end
end

function PlayerManager.carry_blocked_by_cooldown()
	return false
end