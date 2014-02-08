require 'sinatra'

START_BANK = 2_500
BET = 100
MAX_BET = 500
WILD_RATIO = Rational('2/5')

Row = Struct.new(:id, :first_die, :second_die, :start_button_state, :start_bank, :start_dont_pass_line, :start_odds, :end_button_state, :end_bank, :end_dont_pass_line, :end_odds) do
  def button(button_state)
    button_state.nil? ? 'Off' : button_state
  end

  def start_button
    button(start_button_state)
  end
  
  def end_button
    button(end_button_state)
  end

  def landed_on_point?(dice)
    end_button_state.nil? && ![7, 11, 2, 3, 12].include?(dice)
  end

  def won_dont_pass_line?(dice)
    end_button_state.nil? && [2, 3].include?(dice)
  end

  def lost_dont_pass_line?(dice)
    end_button_state.nil? && [7, 11].include?(dice)
  end

  def push_dont_pass_line?(dice)
    end_button_state.nil? && [12].include?(dice)
  end

  def won_3x_point?(dice)
    [4, 10].include?(end_button_state) && 7 == dice
  end

  def won_4x_point?(dice)
    [5, 9].include?(end_button_state) && 7 == dice
  end

  def won_5x_point?(dice)
    [6, 8].include?(end_button_state) && 7 == dice
  end

  def lost_point?(dice)
    end_button_state && end_button_state == dice
  end

  def uneventful?(dice)
    end_button_state && ![7, end_button_state].include?(dice)
  end
end

def roll_die
  (6 * rand).to_i + 1
end

def bet(bank)
  not_wild_ratio = 1 - WILD_RATIO
  wild = bank - START_BANK * not_wild_ratio
  case
  when bank < BET
    end_dont_pass_line = bank
  when wild > (BET * 14)
    end_dont_pass_line = [(wild * Rational('1/7').to_f / 100).round * 100, MAX_BET].min
  else
    end_dont_pass_line = BET
  end
end

def start_row
  id = 1
  first_die = 'N/A'
  second_die = 'N/A'
  start_button_state = nil
  start_bank = START_BANK
  start_dont_pass_line = 0
  start_odds = 0
  end_button_state = nil
  end_dont_pass_line = bet(start_bank)
  end_bank = start_bank - end_dont_pass_line
  end_odds = 0
  Row.new(id, first_die, second_die, start_button_state, start_bank, start_dont_pass_line, start_odds, end_button_state, end_bank, end_dont_pass_line, end_odds)
end

def next_row(id, row)
  first_die = roll_die
  second_die = roll_die
  dice = first_die + second_die

  start_button_state = row.end_button_state
  start_odds = row.end_odds
  start_dont_pass_line = row.end_dont_pass_line
  start_bank = row.end_bank

  point_winnings = lambda do |ratio|
    dont_pass_line_return = start_dont_pass_line * 2
    odds_return = start_odds * (1 + ratio.to_f)
    interim_bank = start_bank + dont_pass_line_return + odds_return
    end_dont_pass_line = bet(interim_bank)
    end_bank = interim_bank - end_dont_pass_line
    [end_dont_pass_line, end_bank]
  end

  case
  when row.landed_on_point?(dice)
    end_button_state = dice
    end_odds = [start_dont_pass_line * 6, start_bank].min
    end_dont_pass_line = start_dont_pass_line
    end_bank = start_bank - end_odds

  when row.won_dont_pass_line?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line = bet(start_bank)
    end_bank = start_bank + (start_dont_pass_line * 2) - end_dont_pass_line

  when row.lost_dont_pass_line?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line = bet(start_bank)
    end_bank = start_bank - end_dont_pass_line

  when row.push_dont_pass_line?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line = start_dont_pass_line
    end_bank = start_bank

  when row.won_3x_point?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line, end_bank = point_winnings.call(Rational('1/2'))

  when row.won_4x_point?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line, end_bank = point_winnings.call(Rational('2/3'))

  when row.won_5x_point?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line, end_bank = point_winnings.call(Rational('5/6'))

  when row.lost_point?(dice)
    end_button_state = nil
    end_odds = 0
    end_dont_pass_line = bet(start_bank)
    end_bank = start_bank - end_dont_pass_line

  when row.uneventful?(dice)
    end_button_state = start_button_state
    end_odds = start_odds
    end_dont_pass_line = start_dont_pass_line
    end_bank = start_bank

  else
    raise "Unknown state after %p" % [row]
  end

  Row.new(id, first_die, second_die, start_button_state, start_bank, start_dont_pass_line, start_odds, end_button_state, end_bank, end_dont_pass_line, end_odds)
end

def get_rows
  rows = []
  row = start_row
  id = 1

  while row.start_bank < (START_BANK * 2) && row.start_bank != 0
    rows.push(row)
    id += 1
    row = next_row(id, row)
  end

  rows
end

get '/' do
  @rows = get_rows
  haml :index
end
