local mvec3_add = mvector3.add
local mvec3_cpy = mvector3.copy
local mvec3_dir = mvector3.direction
local mvec3_lerp = mvector3.lerp
local mvec3_mul = mvector3.multiply
local mvec3_set = mvector3.set
local mvec3_set_z = mvector3.set_z
local math_abs = math.abs
local tmp_vec = Vector3()


-- Boss should basically always be in shooting action
function BossLogicAttack._upd_aim(data, my_data, ...)
	local focus_enemy = data.attention_obj
	local visible = focus_enemy and (focus_enemy.verified or focus_enemy.nearly_visible)
	local aim, shoot, expected_pos
	if focus_enemy then
		if BossLogicAttack._chk_use_throwable(data, my_data, focus_enemy) then
			return
		end

		local time_since_verification = focus_enemy.verified_t and data.t - focus_enemy.verified_t or math.huge
		local time_since_damaged = focus_enemy.dmg_t and data.t - focus_enemy.dmg_t or math.huge
		aim = focus_enemy.verified_dis < my_data.weapon_range.far
		shoot = aim and (visible or time_since_verification < 4) or time_since_damaged < 4
		expected_pos = focus_enemy.last_verified_pos or focus_enemy.verified_pos
	end

	if aim or shoot then
		if visible then
			if my_data.attention_unit ~= focus_enemy.u_key then
				CopLogicBase._set_attention(data, focus_enemy)
				my_data.attention_unit = focus_enemy.u_key
			end
		elseif expected_pos then
			if my_data.attention_unit ~= expected_pos then
				CopLogicBase._set_attention_on_pos(data, expected_pos)
				my_data.attention_unit = expected_pos
			end
		end

		if not my_data.shooting and not my_data.spooc_attack and not data.unit:anim_data().reload and not data.unit:movement():chk_action_forbidden("action") then
			my_data.shooting = data.unit:brain():action_request({
				body_part = 3,
				type = "shoot"
			})
		end
	else
		if my_data.shooting then
			local success = data.unit:brain():action_request({
				body_part = 3,
				type = "idle"
			})
			if success then
				my_data.shooting = nil
			end
		end

		if my_data.attention_unit then
			CopLogicBase._reset_attention(data)
			my_data.attention_unit = nil
		end
	end

	CopLogicAttack.aim_allow_fire(shoot, aim, data, my_data)
end


-- Adjust throwable code to allow for non throwable projectiles
-- Also make the throwing use an actual action so it properly interrupts shooting
-- We're adjusting the throwing vector to always throw at player's feet and add z compensation depending on projectile speed
function BossLogicAttack._chk_use_throwable(data, my_data, focus)
	local throwable = data.char_tweak.throwable
	local throwable_tweak = tweak_data.projectiles[throwable]
	if not throwable_tweak then
		return
	end

	if data.used_throwable_t and data.t < data.used_throwable_t then
		return
	end

	if (not focus.verified) == data.char_tweak.throwable_target_verified then
		return
	end

	if not focus.verified_t or not focus.last_verified_pos or not focus.identified_t or data.t - focus.identified_t < 2 then
		return
	end

	if not focus.verified and (data.t - focus.verified_t < 2 or data.t - focus.verified_t > 8) then
		return
	end

	local mov_ext = data.unit:movement()
	local is_throwable = tweak_data.blackmarket.projectiles[throwable].throwable
	if mov_ext:chk_action_forbidden("action") or data.unit:anim_data().reload or not is_throwable and not mov_ext._allow_fire then
		return
	end

	local throw_dis = focus.verified_dis
	if throw_dis < 400 or throw_dis > (throwable_tweak.launch_speed or 600) * 3 then
		return
	end

	local throw_from
	if is_throwable then
		throw_from = mov_ext:m_rot():y()
		mvec3_mul(throw_from, 40)
		mvec3_add(throw_from, mov_ext:m_head_pos())
		local offset = mov_ext:m_rot():x()
		mvec3_mul(offset, -20)
		mvec3_add(throw_from, offset)
	else
		throw_from = data.unit:inventory():equipped_unit():position()
	end

	local throw_to = focus.verified and focus.m_pos or focus.last_verified_pos
	local slotmask = managers.slot:get_mask("world_geometry")
	mvec3_set(tmp_vec, throw_to)
	mvec3_set_z(tmp_vec, tmp_vec.z - 200)
	local ray = data.unit:raycast("ray", throw_to, tmp_vec, "slot_mask", slotmask)
	if not ray then
		return
	end
	throw_to = ray.hit_position

	local compensation = throwable_tweak.adjust_z ~= 0 and (((throw_dis - 400) / 10) ^ 2) / ((throwable_tweak.launch_speed or 250) / 10) or 0
	mvec3_set_z(throw_to, throw_to.z + compensation)
	mvec3_lerp(tmp_vec, throw_from, throw_to, 0.5)
	if data.unit:raycast("ray", throw_from, tmp_vec, "sphere_cast_radius", 15, "slot_mask", slotmask, "report") then
		return
	end

	data.used_throwable_t = data.t + (data.char_tweak.throwable_cooldown or 15)

	local action_data = {
		body_part = 3,
		type = "act",
		variant = is_throwable and "throw_grenade" or "recoil_single"
	}
	if not data.unit:brain():action_request(action_data) then
		return
	end

	local throw_dir = tmp_vec
	mvec3_dir(throw_dir, throw_from, throw_to)
	ProjectileBase.throw_projectile_npc(throwable, throw_from, throw_dir, data.unit)

	return true
end


-- Check for weapon range to determine wether to move closer
function BossLogicAttack._upd_combat_movement(data, my_data)
	local t = data.t
	local focus_enemy = data.attention_obj
	local enemy_visible = focus_enemy.verified
	local action_taken = data.logic.action_taken(data, my_data)
	local weapon_range = my_data.weapon_range

	if not action_taken then
		if my_data.chase_path_failed_t and t - my_data.chase_path_failed_t <= 1 then
			return
		end

		if my_data.chase_path then
			BossLogicAttack._chk_request_action_walk_to_chase_pos(data, my_data, enemy_visible and focus_enemy.dis < weapon_range.optimal and "walk" or "run")
		elseif not my_data.chase_path_search_id and focus_enemy.nav_tracker then
			local height_diff = math_abs(data.m_pos.z - focus_enemy.m_pos.z)
			local chase = height_diff < 300 or focus_enemy.dis > weapon_range.optimal or my_data.attitude == "engage" and focus_enemy.dis > weapon_range.close
			if not chase and not enemy_visible then
				chase = not focus_enemy.verified_t or t - focus_enemy.verified_t > 2
			end

			if not chase then
				return
			end

			my_data.chase_pos = nil
			local chase_pos = focus_enemy.nav_tracker:field_position()
			local new_chase_pos = CopLogicTravel._get_pos_on_wall(chase_pos, weapon_range.close, nil, nil)
			if chase_pos.x ~= new_chase_pos.x or chase_pos.y ~= new_chase_pos.y then
				my_data.chase_pos = new_chase_pos

				local my_pos = data.unit:movement():nav_tracker():field_position()
				local unobstructed_line = nil

				if math_abs(my_pos.z - my_data.chase_pos.z) < 40 then
					local ray_params = {
						allow_entry = false,
						pos_from = my_pos,
						pos_to = my_data.chase_pos
					}

					if not managers.navigation:raycast(ray_params) then
						unobstructed_line = true
					end
				end

				if unobstructed_line then
					my_data.chase_path = {
						mvec3_cpy(my_pos),
						my_data.chase_pos
					}
				else
					my_data.chase_path_search_id = tostring(data.unit:key()) .. "chase"
					my_data.pathing_to_chase_pos = true

					data.brain:add_pos_rsrv("path", {
						radius = 60,
						position = mvec3_cpy(my_data.chase_pos)
					})
					data.brain:search_for_path(my_data.chase_path_search_id, my_data.chase_pos)
				end
			else
				my_data.chase_path_failed_t = t
			end
		end
	elseif my_data.walking_to_chase_pos and not my_data.use_flank_pos_when_chasing then
		local current_haste = my_data.advancing and my_data.advancing:haste()
		if not current_haste then
			return
		end

		local change_speed
		if current_haste == "run" then
			change_speed = enemy_visible and focus_enemy.dis < weapon_range.close
		else
			change_speed = not enemy_visible or focus_enemy.dis > weapon_range.optimal
		end

		if change_speed then
			BossLogicAttack._cancel_chase_attempt(data, my_data)
		end
	end
end


-- Check new position for being different than the current one
function BossLogicAttack._chk_start_action_move_out_of_the_way(data, my_data)
	local from_pos = data.m_pos
	local reservation = {
		radius = 30,
		position = from_pos,
		filter = data.pos_rsrv_id
	}
	if managers.navigation:is_pos_free(reservation) then
		return
	end

	local to_pos = CopLogicTravel._get_pos_on_wall(from_pos, 500)
	if from_pos.x == to_pos.x and from_pos.y == to_pos.y then
		return
	end

	my_data.advancing = data.brain:action_request({
		variant = "run",
		body_part = 2,
		type = "walk",
		nav_path = {
			mvec3_cpy(from_pos),
			to_pos
		}
	})

	if my_data.advancing then
		my_data.moving_out_of_the_way = my_data.advancing
		BossLogicAttack._cancel_chase_attempt(data, my_data)
		return true
	end
end


-- Update logic every frame
function BossLogicAttack.update(data)
	local my_data = data.internal_data

	if my_data.has_old_action then
		CopLogicAttack._upd_stop_old_action(data, my_data)
		return
	end

	if CopLogicAttack._chk_exit_non_walkable_area(data) or CopLogicIdle._chk_relocate(data) then
		return
	end

	local focus_enemy = data.attention_obj
	if not focus_enemy or focus_enemy.reaction < AIAttentionObject.REACT_AIM then
		BossLogicAttack._upd_enemy_detection(data, true)
		return
	end

	BossLogicAttack._process_pathing_results(data, my_data)

	if focus_enemy and AIAttentionObject.REACT_COMBAT <= focus_enemy.reaction then
		BossLogicAttack._upd_combat_movement(data, my_data)
	else
		BossLogicAttack._cancel_chase_attempt(data, my_data)
	end

	if not data.logic.action_taken then
		BossLogicAttack._chk_start_action_move_out_of_the_way(data, my_data)
	end
end

function BossLogicAttack.queued_update() end
function BossLogicAttack.queue_update() end
