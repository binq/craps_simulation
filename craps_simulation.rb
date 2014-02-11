require 'sinatra'
require 'active_support/core_ext'

START_BANK = 5_000
STOP_BANK = 10_000
BET = 100
MAX_BET = 3_000 / 6
WILD_RATIO = Rational('2/3')
MULTIPLIER = {
  4 => 3, 10 => 3,
  5 => 4, 9 => 4,
  6 => 5, 8 => 5
}
ODDS_RATIO = {
  4 => Rational('1/2'), 10 => Rational('1/2'),
  5 => Rational('2/3'), 9 => Rational('2/3'),
  6 => Rational('5/6'), 8 => Rational('5/6')
}

Row = Struct.new(:id, :dice, :button_state, :returned, :gained_lost, :spent, :bank, :dont_pass_line, :odds) do
  def button
    button_state.nil? ? 'Off' : button_state
  end

  def landed_on_point?(dice)
    button_state.nil? && ![7, 11, 2, 3, 12].include?(dice)
  end

  def won_dont_pass_line?(dice)
    button_state.nil? && [2, 3].include?(dice)
  end

  def lost_dont_pass_line?(dice)
    button_state.nil? && [7, 11].include?(dice)
  end

  def push_dont_pass_line?(dice)
    button_state.nil? && [12].include?(dice)
  end

  def multiplier(dice)
    MULTIPLIER[dice]
  end

  def odds_ratio
    ODDS_RATIO[button_state]
  end

  def won_point?(dice)
    button_state && 7 == dice
  end

  def lost_point?(dice)
    button_state && button_state == dice
  end
end

def roll_die
  (6 * rand).to_i + 1
end

def nearest(num, factor, method=:round)
  num = num.to_f
  factor = factor.to_f
  method = [:round, :floor, :ceil].include?(method) ? method : :round 
  (num / factor).send(method) * factor
end

def nearest_hundred(num)
  nearest(num, 100)
end

def lesser_dollar(num)
  nearest(num, 1, :floor)
end

def bet(bank)
  not_wild_ratio = 1 - WILD_RATIO
  wild_bank = bank - START_BANK * not_wild_ratio
  case
  when bank < BET
    dont_pass_line = bank
  when wild_bank > (BET * 7)
    wild_bet = nearest_hundred(wild_bank * Rational('1/7'))
    dont_pass_line = [wild_bet, MAX_BET].min
  else
    dont_pass_line = BET
  end
end

def start_row
  id = 1
  dice = 'N/A'
  button_state = nil
  dont_pass_line = bet(START_BANK)
  returned = 0
  gained_lost = 0
  spent = dont_pass_line
  bank = START_BANK - dont_pass_line
  odds = 0
  Row.new(id, dice, button_state, returned, gained_lost, spent, bank, dont_pass_line, odds)
end

def next_row(id, row)
  first_die = roll_die
  second_die = roll_die
  dice = first_die + second_die

  case
  when row.landed_on_point?(dice)
    button_state = dice
    odds = [row.dont_pass_line * 6, row.bank].min
    dont_pass_line = row.dont_pass_line
    returned = 0
    gained_lost = 0
    spent = odds
    bank = row.bank + returned + gained_lost - spent

  when row.won_dont_pass_line?(dice)
    button_state = nil
    odds = 0
    dont_pass_line = bet(row.bank)
    returned = row.dont_pass_line
    gained_lost = row.dont_pass_line
    spent = dont_pass_line
    bank = row.bank + returned + gained_lost - spent

  when row.lost_dont_pass_line?(dice)
    button_state = nil
    odds = 0
    dont_pass_line = bet(row.bank)
    returned = 0
    gained_lost = -1 * row.dont_pass_line
    spent = dont_pass_line
    bank = row.bank + returned + 0 - spent

  when row.push_dont_pass_line?(dice)
    button_state = nil
    odds = 0
    dont_pass_line = row.dont_pass_line
    returned = row.dont_pass_line
    gained_lost = 0
    spent = row.dont_pass_line
    bank = row.bank + returned + gained_lost - spent

  when row.won_point?(dice)
    button_state = nil
    odds = 0

    dont_pass_line_return = lesser_dollar(row.dont_pass_line * 2)
    odds_return = lesser_dollar(row.odds * (1 + row.odds_ratio))
    interim_bank = row.bank + dont_pass_line_return + odds_return
    dont_pass_line = bet(interim_bank)
    returned = row.dont_pass_line + row.odds
    gained_lost = (dont_pass_line_return - row.dont_pass_line) + (odds_return - row.odds)
    spent = dont_pass_line
    bank = interim_bank - spent

  when row.lost_point?(dice)
    button_state = nil
    odds = 0
    dont_pass_line = bet(row.bank)
    returned = 0
    gained_lost = -1 * (row.dont_pass_line + row.odds)
    spent = dont_pass_line
    bank = row.bank + returned + 0 - spent

  else
    button_state = row.button_state
    odds = row.odds
    dont_pass_line = row.dont_pass_line
    returned = 0
    gained_lost = 0
    spent = 0
    bank = row.bank + returned + gained_lost - spent
  end

  Row.new(id, dice, button_state, returned, gained_lost, spent, bank, dont_pass_line, odds)
end

def get_results
  results = []

  10_000.times do
    rows = []
    row = start_row
    id = 1

    while true
      rows.push(row)
      break if row.bank > STOP_BANK || row.dont_pass_line == 0
      id += 1
      row = next_row(id, row)
    end

    results.push(rows.last)
  end

  results
end

Stats = Struct.new(:name, :count, :percent, :mean_bank, :standard_deviation_bank, :mean_rounds, :standard_deviation_rounds)

def stats_fun(total_count)
  total_count = total_count.to_f
  built = []
  build = lambda do |name, results|
    count = results.length
    percent = count/total_count
    mean_bank = (results.sum { |row| row.bank } / count).round(2)
    standard_deviation_bank = Math.sqrt(results.sum { |row| (row.bank - mean_bank) ** 2 } / count).round(2)
    mean_rounds = (results.sum { |row| row.id } / count).round
    standard_deviation_rounds = Math.sqrt(results.sum { |row| (row.id - mean_rounds) ** 2 } / count).round
    built.push(Stats.new(name, count, percent, mean_bank, standard_deviation_bank, mean_rounds, standard_deviation_rounds))
    built
  end
  lambda do |*params|
    params.length == 0 ? built : build.(*params)
  end
end

get '/' do
  @results = get_results
  @stats = stats_fun(@results.length).tap do |stats|
    stats.('Total', @results)
    stats.('Win', @results.select { |row| row.bank > STOP_BANK })
    stats.('Lose', @results.select { |row| row.bank == 0 })
    stats.('Draw', @results.select { |row| row.bank <= STOP_BANK && row.bank != 0 })
  end.call
  haml :index
end
