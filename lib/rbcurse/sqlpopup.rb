$LOAD_PATH << "/Users/rahul/work/projects/rbcurse/"

require 'rubygems'
require 'ncurses'
require 'logger'
require 'sqlite3'
require 'lib/ver/ncurses'
require 'lib/ver/keyboard'
require 'lib/ver/keymap'
require 'lib/ver/window'
require 'lib/rbcurse/orderedhash'

##
# given an sql statement, shows the result in a tabular format.
# allows multiple selection of rows.
# shows full screen, so not exactly a popup
# Author: rkumar 2008-11-13 09:14 
#
# TODO: take out key labels into sep class, use ordered hash so deletion possible
#       - remove keymapping stuff into a class
#       - integrate keys_handled with key_lable and keymappings
#       - think about allowing for a got_focus and lost_focus of row

include Ncurses

class SqlPopup

  attr_accessor :header_left   # will print on left what you give
  attr_accessor :labelcolor   # colorpair of label
  attr_accessor :datacolor   # color pair of data
  attr_accessor :promptcolor   # color pair or prompt
  attr_accessor :barcolor   # color pair of bottom bar
  attr_reader :keyhandler, :window
  attr_accessor :mode
  attr_accessor :layout            # window layout, this is a hash
  attr_accessor :show_key_labels   # boolean for whether you want key labels shown at bottom, def true

  def initialize(rows=Ncurses.LINES-1, cols=Ncurses.COLS-1)
    @rows = rows
    @cols = cols
    @startrow = 2 # 1
    @header_row = 0
    @lastrow = Ncurses.LINES-1 # @rows-1

    @promptcolor = 4 # as in alpine
    @labelcolor = 6
    @datacolor = 5
    @barcolor = 2
    @selectioncolor = 4
    @barrow = @lastrow
    @data_frow = 1  # first row of data
    @padrows = Ncurses.LINES-1
    @scrollatrow = @lastrow - 4 # 2 header, 1 footer, 1 prompt 
    @message = nil
    @selected = []
    @stopping = false
    @mode = :control
    @key_labels = get_key_labels
    @layout = { :height => 0, :width => 0, :top => 0, :left => 0 }
    @show_key_labels = true
    if block_given?
      yield self
    end
  end
  def estimate_column_widths
    colwidths = {}
    @content.each_index do |cix|
      break if cix >= 20
      row = @content[cix]
      row.each_index do |ix|
        col = row[ix]
        colwidths[ix] ||= 0
        colwidths[ix] = [colwidths[ix], col.length].max
      end
    end
    total = 0
    colwidths.each_pair do |k,v|
      name = @columns[k.to_i]
      colwidths[name] = v
      total += v
    end
    colwidths["__TOTAL__"] = total
    return colwidths
  end
        

  def print_tabular_data #:yields pad, ix,  row, labelcol, datacol, column_name, column_value
    @prow = 0
    r = @data_frow
    lc = 1
    @pad.clear

    ## LOOP PRINT
    #printstr(@pad,r, lc, "#" , @labelcolor);
    lc += @numpadding+1
    ## COLUMNS
    @colstring = " # "
    @columns.each do |name|
      @colstring << sprintf("%-*s", @colwidths[name]+1, name)
    #  printstr(@win,0, lc, "%s" % name, @labelcolor);
      lc += @colwidths[name]+1
    end
    r = @data_frow
    ## DATA
    @content.each_with_index do |row, rowid|
      lc = 1
      printstr(@pad, r, lc," %*d" % [@numpadding,(rowid+1)] , @datacolor);
      lc += @numpadding+1
      row.each_index do |ix|
        col = row[ix]
        if block_given?
          yield @pad, r, lc, col
        else
          printstr(@pad, r, lc, " "+col , @datacolor);
          lc += @colwidths[ix]+1
        end
      end
      r += 1
    end
    @win.refresh
  end
  def sql(command)
    db = SQLite3::Database.new('../../out/testd.db')
#    db.results_as_hash = true
    #command = %Q{select * from #{tablename} limit 1}
    @columns, *@datarows = db.execute2(command)
    @datatypes = @datarows[0].types
    @content = @datarows
    db.close
    @numpadding = @content.length.to_s.length
    $log.debug("sql: #{command}")
    $log.debug("content len: #{@content.length}")
    $log.debug("content last: #{@content.last}")
#   $log.debug("scrollat: #{@scrollatrow}")
#    $log.debug("cols: #{@columns.inspect}")
#    $log.debug("dt: #{@datatypes.inspect}")
#    $log.debug("row0: #{@datarows[0].inspect}")
#    $log.debug("rows: #{@datarows.inspect}")
  end
  def do_select arow=@prow
    if @selected.include? arow
      @selected.delete arow
      sel = " "; r = arow+1; 
      printstr(@pad, r, col=1, "#{sel}", @datacolor);
    else
      $log.debug("Adding #{arow}")
      @selected << arow
      sel = "X"; r = arow+1; 
      printstr(@pad, r, col=1, "#{sel}", @selectioncolor);
      @message = %q{ '-Next "-Prev ^E-Clear}
      append_key_label '\'', 'NextSel'
      append_key_label '"', 'PrevSel'
      append_key_label 'C-e', 'ClearSel'
      print_key_labels
    end
=begin
    if @selected[@prow].nil?
      @selected[@prow] = "X"
    else
     @selected[@prow] = nil
    end
=end
  end

  def show_focus_on_row row0, tf=true
    color = tf ? @selectioncolor : @datacolor
    r = row0+1 
    return if r > @content_rows
    @pad.mvchgat(y=r, x=1, max=-1, Ncurses::A_NORMAL, color, nil)
#    @pad.highlight_line(color, r, 1, 50)
#   @pad.wtouchln(r,1, 1)
  end
  def oldshow_focus_on_row row0, tf=true
    color = tf ? @selectioncolor : @datacolor
    lc = 1
    r = row0+1
    raise "201 #{r} error #{row0} #{tf}" if r > @content_rows
    printstr(@pad, r, 0, "%-*s" % [Ncurses.COLS," "], color)
    sel = @selected.include?(row0) ? "X" : " "
    printstr(@pad, r, lc, "#{sel}%*d" % [@numpadding, idx=row0+1] , color);
    lc += @numpadding+1
    row = @content[row0]
    row.each_index do |ix|
      col = row[ix]
      if block_given?
        yield @pad, r, lc, col
      else
        printstr(@pad, r, lc, " "+col , color);
        lc += @colwidths[ix]+1
      end
    end
  end
  def run_tabular
    begin
    #@win = WINDOW.new(0,0,0,0)
      @win = VER::Window.new(@layout)
      @window = @win
      # the next line will not obscure footer and header win of prev screen
    #@panel = @win.new_panel
    @panel = @win.panel
    @padrows = [(@content.length) +6, @lastrow+1].max
    @content_rows = @content.length
    @colwidths = estimate_column_widths
    @padcols = @colwidths["__TOTAL__"]  +@columns.length
    $log.debug("cols: #{@padcols} #{@columns.length}")
    @pad = Ncurses.newpad(@padrows,@padcols)
    @padpanel = @pad.new_panel
    Ncurses::Panel.update_panels

    @win.bkgd(Ncurses.COLOR_PAIR(5));
    @pad.keypad(TRUE);
    print_tabular_data

#    Ncurses.refresh();

    @prow = 0; @pcol = 0;
    @toprow = 0
    ## CLEAR clear row
    print_header_left( sprintf("%*s", @cols, " "))
    print_header_left(@header_left) if !@header_left.nil?
    print_header_right(sprintf("Row 1 of %d ", @content.length))
    @win.mvprintw(@header_row+1, 0, "%s", @colstring);
    @win.wrefresh
    show_focus_on_row(0)
    @winrow = 0 # the row on the window we are on
    @pad.prefresh(1,0, @startrow, 0, @rows-2,Ncurses.COLS-1);

    map_keys
    print_key_labels @key_labels
    VER::Keyboard.focus = self
    ensure
      Ncurses::Panel.del_panel(@panel) if !@panel.nil?   
      Ncurses::Panel.del_panel(@padpanel) if !@padpanel.nil?   
      @win.delwin if !@win.nil?
      Ncurses::Panel.del_panel(@message_panel) if !@message_panel.nil?   
      @message_win.delwin if !@message_win.nil?
    end
    return (@selected_data || [])
  end
  def press(key)
#     @message="pressed: #{@mode} - %10p" % key
    # Loop through to get user requests
#   while((ch = @pad.getch()) != KEY_F1 )
#     print_header_left( sprintf("%*s", @cols, " "))
#     print_header_left(@header_left) if !@header_left.nil?
#     @win.wrefresh
      @oldprow = @prow
      @oldtoprow = @toprow
      #c = ch.chr rescue 0
      $log.debug("press key: %s" % key)
#     break if ch == ?q
      #@mapper.press(ch)
      begin
      @keyhandler.press(key)
=begin
      case ch
      when ?[:      # BEGINNING
        goto_start
      when ?]:       # GOTO END
        goto_end
      when KEY_RIGHT,?l
        right
      when KEY_LEFT, ?h
        left
      when KEY_DOWN, ?j
        down
      when KEY_UP,?k
        up
      when 32, ?n:    # SPACE
        space
      when ?-,?p:
        minus
      when KEY_ENTER, 10
        # selection
        enter
        break
      when ?q, ?\,
        stop
        break
      when ?g
        handle_goto_ask
      when ?/:
        do_search_ask
      when ?\C-n:
        do_search_next
      when ?\C-p:
        do_search_prev
      when ?x:
        do_select
      when ?':
        do_next_selection
      when ?":
        do_prev_selection
      when ?\C-e:
        do_clear_selection
      end
=end
      break if stopping?
      #@win.wclear
      @toprow = @prow if @prow < @toprow   # ensre search could be 
      @toprow = @prow if @prow > @toprow + @scrollatrow   
      @winrow = @prow - @toprow

      if @content.length - @toprow < @scrollatrow and  @toprow != @oldtoprow
        window_erase @win
      end
      print_header_left( sprintf("%*s", @cols, " "))
      print_header_left(@header_left) if !@header_left.nil?
      print_header_right(sprintf("Row %d of %d ", @prow+1, @content.length))
      @win.mvprintw(@header_row+1, 0, "%s", @colstring[@pcol..-1]); # scrolls along with pcol
      printstr(@win, @barrow-1, Ncurses.COLS-@message.length,@message, @barcolor) if !@message.nil?
=begin
      if @message.nil?
        clear_message
      end
=end
      @win.refresh
      show_focus_on_row(@oldprow, false)
      show_focus_on_row(@prow)
    # $log.debug("tr:wr:pr #{@toprow} #{@winrow} #{@prow}")
      @pad.prefresh(@toprow+1,@pcol, @startrow,0, @rows-2,Ncurses.COLS-1) 
      #@win.wclrtobot # gives less flicker since wclear sems to refresh immed
      Ncurses::Panel.update_panels
      if !@message.nil?
        print_message @message 
        @message = nil
      end

    rescue ::Exception => ex
      $log.debug ex
      show(ex.message)
    end
    #end # while

  end # run

  def do_next_selection
    return if @selected.length == 0 
    row = @selected.sort.find { |i| i > @prow }
    row ||= @prow
    @prow = row
  end
  def do_prev_selection
    return if @selected.length == 0 
    row = @selected.sort{|a,b| b <=> a}.find { |i| i < @prow }
    row ||= @prow
    @prow = row
  end
  def do_clear_selection
    @selected.each {|sel| do_select(sel)}
  end
  def get_selected_data
    ret = []
    @selected.each { |sel| ret << @content[sel] }
    return ret
  end

  def handle_goto_ask
    line = getstring "Enter row to go to:"
    oldrow = @prow
    @prow = line.to_i
    @prow -= 1 if @prow > 0
    if @prow > @content.length
      @prow = oldrow
      Ncurses.beep
    #  next
    end
  end
    def do_search_ask
      regex = getstring "Enter pattern to search for:"
      res = []
      @content.each_with_index do |row, ix| res << ix if row.grep(/#{regex}/) != [] end
      if res.length > 0
        @prow = res[0]
        append_key_label 'C-n', 'NextMatch'
        append_key_label 'C-p', 'PrevMatch'
        print_key_labels
      end
      @message = "Matched %d for %s." % [res.length, regex]
      @search_indices = res
      @search_index = 0
    end
    def do_search_next
      if @search_indices == []
        Ncurses.beep
      end
      @search_index += 1
      if @search_index >= @search_indices.length
        @search_index = 0
      end
      @prow = @search_indices[@search_index]
    end
    def do_search_prev
      if @search_indices == []
        Ncurses.beep
      end
      @search_index -= 1
      if @search_index < 0
        @search_index = @search_indices.length-1
      end
      @prow = @search_indices[@search_index]
    end

    def putstring prompt, r=@lastrow-2, c=1, color = @promptcolor
      clear_error @win, r, color
      printstr(@win,r, c, prompt, color);
    end
    def getstring prompt, r=@lastrow-2, c=1, maxlen = 10, color = @promptcolor
      clear_error @win, r, color
      printstr(@win,r, c, prompt, color);
      ret = ''
      Ncurses.echo();
      @win.attron(Ncurses.COLOR_PAIR(color))
      begin
        @win.mvwgetnstr(r,c+prompt.length+1,ret,maxlen)
      rescue Interrupt => err
        # C-c
        ret = ''
      end
      @win.attroff(Ncurses.COLOR_PAIR(color))
      Ncurses.noecho();
      return ret
    end
    def clear_error win, r = @lastrow, color = @promptcolor
      printstr(win, r, 0, "%-*s" % [Ncurses.COLS," "], color)
    end
    def print_header_left(string)
      @win.attron(Ncurses.COLOR_PAIR(6))
      @win.mvprintw(@header_row, 0, "%s", string);
      @win.attroff(Ncurses.COLOR_PAIR(6))
    end
    def print_header_right(string)
      @win.attron(Ncurses.COLOR_PAIR(6))
      @win.mvprintw(@header_row, @cols-string.length, "%s", string);
      @win.attroff(Ncurses.COLOR_PAIR(6))
    end
    def printstr(pad, r,c,string, color)
      pad.attron(Ncurses.COLOR_PAIR(color))
      pad.mvprintw(r, c, "%s", string);
      pad.attroff(Ncurses.COLOR_PAIR(color))
    end
  def print_this(win, text, color, x, y)
    if(win == nil)
      raise "win nil in printthis"
    end
    color=Ncurses.COLOR_PAIR(color);
    win.attron(color);
    #win.mvprintw(x, y, "%-40s" % text);
    win.mvprintw(x, y, "%s" % text);
    win.attroff(color);
    win.refresh
  end
 
    def goto_start
      @prow = 0
      @toprow = @prow
      @winrow = 0 # 2008-11-12 16:32 
    end
    def goto_end
      @prow = @content_rows-1 
      #@toprow = @prow
      #@winrow = 0     # not putting this was cause prow < toprow !!
      @toprow = @prow - @scrollatrow # ensure screen is filled when we show last. so clear not required
         ## except what if very few rows
      @winrow = @scrollatrow
    end
    def right
      @pcol += 20 if @pcol + 50 < @padcols
      window_erase @win
    end
    def left
      @pcol -= 20 if @pcol > 0
      @pcol = 0 if @pcol < 0
    end
    def down
#     $log.debug "inside down"
      if @prow >= @content_rows-1
        Ncurses.beep
    #    next
return
      end
      if @winrow < @scrollatrow # 20
        @winrow += 1    # move cursor down
      else
        @toprow += 1    # scroll down a row
      end
      @prow += 1        # incr pad row
    end
    def up # UP
#     $log.debug "inside up"
      if @prow <= 0
        Ncurses.beep
        @prow = 0
        #  next
return
      else
        @prow -= 1 
      end
      if @winrow > 0 
        @winrow -= 1
      else
        @toprow -= 1 if @toprow > 0
      end
      $log.error("ERR !!!! #{@winrow} pr #{@prow} tr #{@toprow}") if @prow < @toprow
      @toprow = @prow if @prow < @toprow
    end
    def space
      #if @prow + @scrollatrow+1 >= @content_rows
      if @toprow + @scrollatrow+1 >= @content_rows
    #    next
      else
        @prow += @scrollatrow+1 # @rows-2
      $log.debug "space pr #{@prow}"
        @toprow = @prow
      end
    end
    def minus
      if @prow <= 0
        Ncurses.beep
        @prow = 0
        #next
      else
        @prow -=  (@scrollatrow+1) #(@rows-2)
        @prow = 0 if @prow < 0
      end
      @toprow = @prow
    end
    def enter
      @selected_data = get_selected_data
      $log.debug("RETURN: #{@selected_data.inspect}")
      stop
    end
    def show string
      @message = string
    end
=begin
    def press(key)
      @keyhandler.press(key)
      @message="pressed: #{@mode} - %10p" % key
    rescue ::Exception => ex
      $log.debug ex
      #show(ex.message)
    end
=end
    def map_keys
      #@keyhandler = VER::KeyHandler.new(self)
=begin
      @mapper.let :insert do
       map(/^([[:print:]])$/){ view.show(@arg) }
       map('enter'){ view.show(:enter) }
        map('esc'){ view.mode = :control }
        map('C-x'){ view.mode = :control }
        map('C-c'){ view.mode = :control }
        map('C-q'){ stop }
      end
=end

      @mapper = Mapper.new(self)
      @keyhandler = @mapper
      raise "NIL" if @mapper.nil?
      @mapper.let :control do

        map('C-x', 'C-d'){ view.down }
        map('C-x', 'C-u'){ view.up }
        map('C-x', 'q'){ view.stop }
        map('C-x', 'C-s'){ view.do_search_ask }
        map('C-x', 'C-x'){ view.do_select }
        map('C-s'){ view.mode = :cx }
        map('q'){ view.stop }
        map('space'){ view.space }
        map('n'){ view.space }
        map('j'){ :down }
        map('k'){ view.up }
        map('p'){ view.minus }
      map('[') { view.goto_start }
      map(']') { view.goto_end }
      map('-') { view.minus }

      map('right') { view.right}
      map('l') { view.right}
      map('left') {view.left}
      map('h') {view.left}
      map('down') { view.down }
      map('j') { view.down }
      map('up') { view.up }
      map('enter') { view.enter  }
      map('g') { view.handle_goto_ask }
      map('/') { view.do_search_ask }
      map('C-n') { view.do_search_next }
      map('C-p') { view.do_search_prev }
      map('x') { view.do_select }
      map('\'') { view.do_next_selection }
      map('"') { view.do_prev_selection }
      map('C-e') { view.do_clear_selection }
      map(/^([[:print:]])$/){ #view.show("Got printable: #{@arg}") 
      }
#        map([/^(\d)$/, 'n']){ d.times(view.space) }
#  map([/^(\d\d?)$/, 'j']){ @arg.to_i.times {view.down};view.show("d then #@arg")}
#  map([/^(\d\d?)$/, 'k']){ @arg.to_i.times {view.up}}
    #map([/^(\d)$/, 'j']){ d.times(view.down) }
#        map(['j', /^(\d)$/]){ d.times(view.down) }


        map('C-q'){ view.stop }
=begin
  macro('h',       'left')
  macro('j',       'down')
  macro('k',       'up')
  macro('l',       'right')
=end
 
=begin
# allows us to do 5j, 12k, 2l etc
        count_map(7, /^down|j$/){ @count.times{ view.down } }
        count_map(7, /^up|k$/){ @count.times{ view.up } }
        count_map(7, /^left|h$/){ @count.times{ view.left } }
        count_map(7, /^right|l$/){ @count.times{ view.right } }
  macro('e',       'j')
        # alias ZZ to save and quit
#       macro('Z Z', 'C-s C-q')
#       macro('x', 'Z Z')
#       macro('X', 'x')
=end
      end
      @mapper.let :cx do
        map('c'){ view.show(:c) }
        map('a'){ view.show(:a) }
        map('r'){ view.show(:r) }
        map('q'){ view.stop }
        map('i'){ view.mode = :control }
      end
      #@mapper = Mapper.new(self)
      # map keys, methods, desc=""
=begin
      @mapper.map [?[], :goto_start
      @mapper.map  [?]], :goto_end
      @mapper.map [32,?n], :space
      @mapper.map [?-,?p], :minus

      @mapper.map  [KEY_RIGHT,?l], :right
      @mapper.map  [KEY_LEFT, ?h], :left
      @mapper.map  [KEY_DOWN, ?j], :down
      @mapper.map  [KEY_UP,?k], :up
      @mapper.map  [KEY_ENTER, 10], :enter 
      @mapper.map  [?q, ?\\], :stop!
      @mapper.map  [?g], :handle_goto_ask
      @mapper.map  [?/], :do_search_ask
      @mapper.map  [?\C-n], :do_search_next
      @mapper.map  [?\C-p], :do_search_prev
      @mapper.map  [?x], :do_select
      @mapper.map  [?'], :do_next_selection
      @mapper.map  [?"], :do_prev_selection
      @mapper.map  [?\C-e], :do_clear_selection
=end
      end
    # from VER
    def stopping?
      @stop
    end

    # without this system hangs if unknown key presed
    def info(message)
      @message = message
      # sorry, hardcoded right now...
    end

    def stop
      @stop = true
      throw(:close)
    end
    def get_key_labels
      key_labels = [
        ['g', 'Goto'], ['/', 'Search'],
        ['x', 'Sel'], ['C-e', 'ClrSel'],
        ['Spc','PgDn'], ['-','PgUp']
      ]
      return key_labels
    end
    def append_key_label key, label
      @key_labels << [key, label] if !@key_labels.include? [key, label]
    end
    def print_key_labels(arr = @key_labels)
      return if !@show_key_labels
        
        posx = 0
        even = []
        odd = []
        arr.each_index { |i|
          if i % 2 == 0
            #arr[i+1] = ['',''] if arr[i+1].nil?
            nextarr = arr[i+1] || ['', '']
            keyw = [arr[i][0].length, nextarr[0].length].max
            labelw = [arr[i][1].length, nextarr[1].length].max

            even << [ sprintf("%*s", keyw,  arr[i][0]), sprintf("%-*s", labelw,  arr[i][1]) ]
            odd << [ sprintf("%*s", keyw,  nextarr[0]), sprintf("%-*s", labelw,  nextarr[1]) ]
            $log.debug("loop even: #{even.inspect}")
          else
          end
        }
        $log.debug("even: #{even.inspect}")
        $log.debug("odd : #{odd.inspect}")
        posy = @barrow-1
        print_key_labels_row(posy, posx, even)
        posy = @barrow
        print_key_labels_row(posy, posx, odd)
        @win.wrefresh   # needed else secod row not shown after askchoice XXX
      end
      def print_key_labels_row(posy, posx, arr)
        $footer_color_pair ||= 6
        padding = 8
        padding = 4 if arr.length > 5
        padding = 0 if arr.length > 7
        my_form_win = @win
        print_this(@win, "%-*s" % [Ncurses.COLS," "], $footer_color_pair, posy, 0)
        arr.each do |kl|
          key = kl[0]
          lab = kl[1]
          if key !="" # don't print that white blank space for fillers
            color_pair=2
            x = posx +  (key.length - key.strip.length)
            my_form_win.attron(Ncurses.COLOR_PAIR(color_pair))
            my_form_win.mvprintw(posy, x, "%s" % kl[0].strip );
            my_form_win.attroff(Ncurses.COLOR_PAIR(color_pair))
          end
          color_pair=$footer_color_pair
          posx = posx + kl[0].length 
          my_form_win.attron(Ncurses.COLOR_PAIR(color_pair))
    
          #lab = sprintf(" %s %*s" , kl[1], padding, " ");
          lab = sprintf(" %s %s" , kl[1], " "*padding);
          my_form_win.mvprintw(posy, posx, lab)
          my_form_win.attroff(Ncurses.COLOR_PAIR(color_pair))
          posx = posx +  lab.length
      end
    end
    def window_erase win
        win.werase # gives less flicker since wclear sems to refresh immed
        print_key_labels @key_labels
    end
    def print_message text
      putstring text, @lastrow-2, 1, color = @promptcolor
    end

    def oldprint_message text
      if @message_win.nil?
        layout = { :height => 2, :width => 0, :top => Ncurses.LINES-4, :left => 0 }
        @message_win = VER::Window.new(layout)
        #  @message_win = WINDOW.new(1,0,Ncurses.LINES-3,0)
        @message_panel = @message_win.panel
      end
      $error_color_pair ||= 7 # 7
      $log.debug("inside printmessage:" + text);
      print_this(@message_win, "M:"+text, $error_color_pair, 1, 1)
      @message_win.show
      @message_win.wrefresh
    end
    def clear_message
      @message_win.hide if !@message_win.nil?
      clear_error @win, r=@lastrow-2, color=@promptcolor
    end
    ## ADD HERE
end # class PadReader
class Mapper
  attr_reader :keymap
  attr_reader :view
  attr_accessor :mode
  attr_reader :keys
  def initialize handler
    #@handler = handler
    @view = handler       # caller program
    @keys = {}
    @mode = nil  # used when defining
    @pendingkeys = nil
    @prevkey = nil   # in case of a key sequence such as C-x C-c, will have C-x
    @arg = nil # regex matched this key.
  end
  def let mode, &block
    h = OrderedHash.new
    @keys[mode] = h
    @mode = mode
    instance_eval(&block)
    $log.debug("KEYS: #{@keys[mode].inspect}")
  end
  def map(*args, &block)
    if block_given?
      # We check for cases like C-x C-c etc. Only 2 levels.
      #args = arg.split(/ +/)
      if args.length == 2
        @keys[@mode][args[0]] ||= OrderedHash.new
        @keys[@mode][args[0]][args[1]]=block
      else
        # single key or control key
        @keys[@mode][args[0]]=block
      end
    else
       #no block, last arg shold be a symbol
       symb = args.pop
       raise "If block not passed, last arg should be a method symbol" if !symb.is_a? Symbol
       if args.length == 2
         @keys[@mode][args[0]] ||= OrderedHash.new
         @keys[@mode][args[0]][args[1]]=symb
       else
         # single key or control key
         @keys[@mode][args[0]]=symb
       end
    end
  end

  ## manages key pressing
  # takes care of multiple key combos too
  def press key
    $log.debug("press Got: #{key}")
    # for a double key combination such as C-x C-c this has the set of pending keys to check against
    if @pendingkeys != nil
      blk = @pendingkeys[key]
    else
      # this is the regular single key mode
      #blk = @keys[@view.mode][key]
      blk = match(key)
    end
    # this means this key expects more keys to follow such as C-x could
    if blk.is_a? OrderedHash
      @pendingkeys = blk
      @prevkey = key
      return
    end
    if blk.nil? # this should go up XXX
      if !@pendingkeys.nil?
        view.info("%p not valid in %p. Try: #{@pendingkeys.keys.join(', ')}" % [key, @prevkey]) # XXX
      else
        view.info("%p not valid in %p. " % [key, @view.mode]) 
      end
      return
    end
    # call the block or symbol - our user defined key mappings use symbols
    if blk.is_a? Symbol
      @view.send(blk)
    else
      blk.call
    end
    @prevkey = nil
    @pendingkeys = nil
  end
  def match key
#       $log.debug "MATCH #key "
      #blk = @keys[@view.mode][key]
    @keys[@view.mode].each_pair do |k,v|
#     $log.debug "LOOP #{k.class}, #{k}, #{v} "
      case k.class.to_s
      when "String"
        return v if k == key
      when "Regexp"
#       $log.debug "REGEX #key , #k, #{k.match(key)}"
        if !k.match(key).nil?
          @arg = key
          return v 
        end
      else
        $log.error "MATCH: Unhandled class #{k.class} "
      end
    end
    return nil
  end
end

  if $0 == __FILE__
    # Initialize curses
    begin
      VER::start_ncurses
      Ncurses.start_color();
=begin
      stdscr = Ncurses.initscr();
      Ncurses.start_color();
      Ncurses.cbreak();
      Ncurses.noecho();
      Ncurses.keypad(stdscr, true);
=end

      # Initialize few color pairs 
      Ncurses.init_pair(1, COLOR_RED, COLOR_BLACK);
      Ncurses.init_pair(2, COLOR_BLACK, COLOR_WHITE);
      Ncurses.init_pair(3, COLOR_BLACK, COLOR_BLUE);
      Ncurses.init_pair(4, COLOR_YELLOW, COLOR_RED); # for selected item
      Ncurses.init_pair(5, COLOR_WHITE, COLOR_BLACK); # for unselected menu items
      Ncurses.init_pair(6, COLOR_WHITE, COLOR_BLUE); # for bottom/top bar
      Ncurses.init_pair(7, COLOR_WHITE, COLOR_RED); # for error messages

      # Create the window to be associated with the form 
      # Un post form and free the memory
      $log = Logger.new("view.log")
      $log.level = Logger::DEBUG
    catch(:close) do
      tp = SqlPopup.new
      tp.header_left = "Contracts"
      tp.labelcolor = 5
      tp.datacolor = 2
      tp.sql("select * from contacts ")
      tp.labelcolor = 2
      tp.datacolor = 5
      tp.run_tabular
 #     VER::Keyboard.focus = tp
    end
  rescue => ex
  ensure
    VER::stop_ncurses
    $log.debug( ex) if ex
    $log.debug(ex.backtrace.join("\n")) if ex
    p ex if ex
    p(ex.backtrace.join("\n")) if ex
  end
 end
