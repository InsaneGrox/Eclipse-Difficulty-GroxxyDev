--This code is literally just to remove shooting while interacting, I'd love to figure out a cleaner way to do this than just replacing the function but I'm lazy.
Hooks:OverrideFunction(PlayerStandardVR, "_check_action_primary_attack",
function(self, t, input)
	local new_action1, new_action2 = nil
	local action_wanted = input.btn_primary_attack_state or input.btn_primary_attack_release or input.btn_akimbo_fire_state or input.btn_akimbo_fire_release

	if action_wanted then
		local action_forbidden = self:_changing_weapon() or self:_interacting() or self:_is_meleeing() or self:_is_throwing_projectile(input) or self:_is_deploying_bipod() or self:is_switching_stances()

		if not action_forbidden then
			self._queue_reload_interupt = nil

			self._ext_inventory:equip_selected_primary(false)

			local weapon_hand_id = self._unit:hand():get_active_hand_id("weapon")

			if self._equipped_unit then
				if table.contains(self._equipped_unit:base():weapon_tweak_data().categories, "bow") then
					local bow_hand_id = self._unit:hand():get_active_hand_id("bow")

					if not bow_hand_id or not self._unit:hand():current_hand_state(bow_hand_id):can_grip_string() then
						input.btn_primary_attack_press = nil
						input.btn_primary_attack_state = nil
						input.btn_primary_attack_release = nil
					end
				end

				if self._equipped_unit:base().akimbo then
					new_action2 = self:_check_fire_per_weapon(t, input.btn_akimbo_fire_press, input.btn_akimbo_fire_state, input.btn_akimbo_fire_release, self._equipped_unit:base()._second_gun:base(), true)
				end

				new_action1 = self:_check_fire_per_weapon(t, input.btn_primary_attack_press, input.btn_primary_attack_state, input.btn_primary_attack_release, self._equipped_unit:base())
			end
		elseif self:_is_reloading() and self._equipped_unit:base():reload_interuptable() and (input.btn_primary_attack_press or input.btn_akimbo_fire_press) then
			self._queue_reload_interupt = true
		end
	end

	if self._shooting_weapons then
		if not new_action1 and not new_action2 then
			self:_check_stop_shooting()
		else
			if not new_action1 and self._shooting_weapons[1] then
				self:_stop_shooting_weapon(1)
			end

			if not new_action2 and self._shooting_weapons[2] then
				self:_stop_shooting_weapon(2)
			end
		end
	end
end)