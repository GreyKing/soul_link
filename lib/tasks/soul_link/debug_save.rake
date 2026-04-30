namespace :soul_link do
  desc "Re-enqueue ParseSaveDataJob for every session that has save_data — use after a parser offset fix to refresh the parsed_* cache columns without waiting for the next in-game save"
  task reparse_all_saves: :environment do
    sessions = SoulLinkEmulatorSession.where.not(save_data: nil).order(:id)
    if sessions.empty?
      puts "No sessions with save_data."
      next
    end

    sessions.each do |s|
      SoulLink::ParseSaveDataJob.perform_later(s)
      puts "Enqueued reparse for session id=#{s.id} player=#{s.discord_user_id}"
    end
    puts "Enqueued #{sessions.size} reparse job(s)."
  end

  desc "Hex-dump the trainer-block region of every session's SRAM (for parser offset debugging)"
  task debug_save_offsets: :environment do
    sessions = SoulLinkEmulatorSession.where.not(save_data: nil).order(:id)
    if sessions.empty?
      puts "No sessions with save_data."
      next
    end

    sessions.each do |s|
      bytes = s.save_data
      next unless bytes.is_a?(String)

      size_note = bytes.bytesize == 0x80000 ? "" : " (UNEXPECTED — should be 0x80000)"
      puts "=" * 70
      puts "Session id=#{s.id} player=#{s.discord_user_id} bytes=0x#{bytes.bytesize.to_s(16)}#{size_note}"

      [ 0x0000, 0x40000 ].each do |slot_off|
        slot = bytes.byteslice(slot_off, 0x40000)
        next if slot.nil? || slot.bytesize < 0xCF2C

        counter    = slot.byteslice(0xCF18, 4)&.unpack1("V")
        stored_crc = slot.byteslice(0xCF2A, 2)&.unpack1("v")

        # Compute CRC over bytes 0..0xCF18 (everything before footer) to
        # confirm the slot is the active/valid one.
        body  = slot.byteslice(0, 0xCF18)
        crc   = 0xFFFF
        body.each_byte do |b|
          crc ^= (b << 8)
          8.times { crc = (crc & 0x8000).zero? ? (crc << 1) : ((crc << 1) ^ 0x1021); crc &= 0xFFFF }
        end
        valid = crc == stored_crc ? "VALID" : "INVALID (computed 0x#{'%04X' % crc})"

        puts "Slot @0x#{slot_off.to_s(16).rjust(5, '0')}: save_counter=#{counter} stored_crc=0x#{'%04X' % stored_crc.to_i} #{valid}"

        # Trainer-block region: name @ 0x68, money @ 0x7C (verified working),
        # badges + play-time + map-id all suspect. Dump 0x60-0xE0 to expose
        # the true offsets by content.
        (0x60..0xE0).step(16) do |off|
          chunk = slot.byteslice(off, 16)
          hex   = chunk.bytes.map { |b| "%02X" % b }.join(" ")
          ascii = chunk.bytes.map { |b| (b >= 32 && b < 127) ? b.chr : "." }.join
          puts "  0x%04X: %s  |%s|" % [ off, hex, ascii ]
        end
      end
      puts
    end
  end
end
