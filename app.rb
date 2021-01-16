# encoding: utf-8

require "bundler"
Bundler.require

require "sinatra/reloader"

# ISBN をハイフン付き 13 桁化
# 不正な ISBN に対しては nil を返す
def normal_isbn(isbn)
  Lisbn.new(isbn.to_s).parts&.join("-")
end

class Book
  def initialize(data)
    @data = data
  end

  def id
    @data["id"]
  end

  # 二つの Book 配列の差分
  # 共通，左のみ，右のみの配列を返す
  # 共通部分は左と右のペアの配列
  def self.difference(books1, books2)
    # ISBN をキーとするハッシュに
    books1 = books1.to_h{ |book| [book.isbn, book]}
    books2 = books2.to_h{ |book| [book.isbn, book]}

    isbns1 = books1.keys
    isbns2 = books2.keys

    common = (isbns1 & isbns2).map do |isbn|
      [books1[isbn], books2[isbn]]
    end
    books12 = (isbns1 - isbns2).map{ |isbn| books1[isbn] }
    books21 = (isbns2 - isbns1).map{ |isbn| books2[isbn] }
    [common, books12, books21]
  end
end

class CalilBook < Book
  def isbn
    normal_isbn @data["isbn"]
  end

  def title
    @data["title"]
  end
end

class EnjuBook < Book
  def isbn
    isbn_identifier = @data["identifiers"].find{ |id| id["identifier_type"] == "isbn" }
    normal_isbn isbn_identifier&.fetch("body")
  end

  def title
    @data["original_title"]
  end
end

# カーリルの検索
# CalilBook の配列を返す
def unitrad(query)
  base_url = "https://unitrad-tokyo-1.calil.jp/v1"
  response = Faraday.get "#{base_url}/search",
    region: 'gk-2002002-x8zrb',
    free: query
  data = JSON.parse(response.body)
  while data['running']
    response = Faraday.get "#{base_url}/polling",
      uuid: data['uuid'],
      timeout: 10,
      version: data['version']
    data = JSON.parse(response.body)
  end

  data["books"].map{ |book| CalilBook.new(book) }
end

# Enju の検索
# EnjuBook の配列を返す
def enju(query)
  url = "https://dev.next-l.jp/manifestations.json"
  response = Faraday.get url,
      utf8: '✓',
      query: query,
      per_page: '1000'
  data = JSON.parse(response.body)
  data["results"].map{ |book| EnjuBook.new(book) }
end

class CompareApp < Sinatra::Base
  helpers Sinatra::UrlForHelper

  configure :development do
    register Sinatra::Reloader
  end

  helpers do
    def h(text)
      Rack::Utils.escape_html(text)
    end

    def enju_book_url(id)
      "https://dev.next-l.jp/manifestations/#{id}"
    end

    def calil_book_url(id)
      "https://private.calil.jp/bib/gk-2002002-x8zrb/#{id}"
    end
  end

  get "/style.css" do
    sass :style
  end

  get '/' do
    @q = params[:q].to_s.gsub(/[[:space:]]+/, " ").strip

    unless @q.empty?
      @enju_items, @enju_items_no_isbn = enju(@q).partition(&:isbn)
      @calil_items, @calil_items_no_isbn = unitrad(@q).partition(&:isbn)

      @enju_items.sort_by!(&:isbn)
      @calil_items.sort_by!(&:isbn)

      @common, @diff_enju_calil, @diff_calil_enju =
        Book.difference(@enju_items, @calil_items)
    end

    slim :index
  end
end
